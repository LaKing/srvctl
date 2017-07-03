// Copyright 2014, 2015 tgic<farmer1992@gmail.com>. All rights reserved.
// this file is governed by MIT-license
//
// https://github.com/tg123/sshpiper

// LaKing@D250.hu 2017.06.25
// this file has been tuned to run on srvctl-controlled hosts

package main

import (
        "bufio"
        "bytes"
        "fmt"
        "io/ioutil"
        "net"
        "os"
        "regexp"
        "strings"
        "os/exec"


        "github.com/tg123/sshpiper/ssh"
)

type userFile string

var (
        UserAuthorizedKeysFile userFile = "authorized_keys"
        UserKeyFile            userFile = "srvctl_id_rsa"
        UserUpstreamFile       userFile = "sshpiper_upstream"

        usernameRule *regexp.Regexp
)

func init() {
        // Base username validation on Debians default: https://sources.debian.net/src/adduser/3.113%2Bnmu3/adduser.conf/#L85
        // -> NAME_REGEX="^[a-z][-a-z0-9_]*\$"
        // The length is limited to 32 characters. See man 8 useradd: https://linux.die.net/man/8/useradd

        // srvctl -  we use this custom regexp
        usernameRule, _ = regexp.Compile("^[a-z][-a-z0-9\\.]{0,31}_[-a-z0-9\\.]{0,256}_[-a-z0-9]{0,31}$")
        
        logger.Printf("sshpiperd modified for srvctl3 (@SRVCTL_VERSION)")
}

func userSpecFile(user, file string) string {
        return fmt.Sprintf("%s/%s/%s", config.WorkingDir, user, file)
}

func (file userFile) read(user string) ([]byte, error) {
        return ioutil.ReadFile(userSpecFile(user, string(file)))
}

func (file userFile) realPath(user string) string {
        return userSpecFile(user, string(file))
}

// return error if other and group have access right
func (file userFile) checkPerm(user string) error {
        filename := userSpecFile(user, string(file))
        f, err := os.Open(filename)
        if err != nil {
                return err
        }
        defer f.Close()

        fi, err := f.Stat()
        if err != nil {
                return err
        }

        if config.NoCheckPerm {
                return nil
        }

        if fi.Mode().Perm()&0077 != 0 {
                return fmt.Errorf("%v's perm is too open", filename)
        }

        return nil
}

// return false if username is not a valid unix user name
// this is for security reason
func checkUsername(user string) bool {
        if config.AllowBadUsername {
                return true
        }

        return usernameRule.MatchString(user)
}

func parseUpstreamFile(data string) (string, string) {

        var user string
        var line string

        r := bufio.NewReader(strings.NewReader(data))

        for {
                var err error
                line, err = r.ReadString('\n')
                if err != nil {
                        break
                }

                line = strings.TrimSpace(line)

                if line != "" && line[0] != '#' {
                        break
                }
        }

        t := strings.SplitN(line, "@", 2)

        if len(t) > 1 {
                user = t[0]
                line = t[1]
        }

        // test if ok
        if _, _, err := net.SplitHostPort(line); err != nil && line != "" {
                // test valid after concat :22
                if _, _, err := net.SplitHostPort(line + ":22"); err == nil {
                        line += ":22"
                }
        }
        return line, user
}

func findUpstreamFromUserfile(conn ssh.ConnMetadata) (net.Conn, string, error) {
        user := conn.User()

        // srvctl decompose the composit username
        //sc_user := strings.Split(user, "_")[0]
        sc_ve := strings.Split(user, "_")[1]
        sc_as := strings.Split(user, "_")[2]

        if !checkUsername(user) {
                return nil, "", fmt.Errorf("The regexp check failed on the username.")
        }

        addr := sc_ve + ":22"
        mappedUser := sc_as

        if addr == "" {
                return nil, "", fmt.Errorf("empty addr")
        }

        logger.Printf("mapping user [%v] to [%v@%v]", user, mappedUser, addr)

        c, err := net.Dial("tcp", addr)
        if err != nil {
                return nil, "", err
        }

        return c, mappedUser, nil
}

func mapPublicKeyFromUserfile(conn ssh.ConnMetadata, key ssh.PublicKey) (signer ssh.Signer, err error) {
        composite_username := conn.User()
        user := strings.Split(composite_username, "_")[0]

        if !checkUsername(composite_username) {
                return nil, fmt.Errorf("The regexp check failed on the username..")
        }

        defer func() { // print error when func exit
                if err != nil {
                        logger.Printf("mapping private key error: %v, public key auth denied for [%v] from [%v]", err, user, conn.RemoteAddr())
                }
        }()

        // srvctl - we need all public keys
        cmd := exec.Command("/bin/bash","-c","cat " + config.WorkingDir + "/" + user + "/*.pub /var/srvctl3/share/common/authorized_keys")
        stdout, err := cmd.Output()

        if err != nil {
                println(err.Error())
                return
        }

        keydata := key.Marshal()

        var rest []byte
        rest = stdout

        var authedPubkey ssh.PublicKey

        for len(rest) > 0 {
                authedPubkey, _, _, rest, err = ssh.ParseAuthorizedKey(rest)

                if err != nil {
                        return nil, err
                }

                if bytes.Equal(authedPubkey.Marshal(), keydata) {
                        err = UserKeyFile.checkPerm(user)
                        if err != nil {
                                return nil, err
                        }

                        var privateBytes []byte
                        privateBytes, err = UserKeyFile.read(user)
                        if err != nil {
                                return nil, err
                        }

                        var private ssh.Signer
                        private, err = ssh.ParsePrivateKey(privateBytes)
                        if err != nil {
                                return nil, err
                        }

                        // in log may see this twice, one is for query the other is real sign again
                        logger.Printf("auth succ, using mapped private key [%v] for user [%v] from [%v]", UserKeyFile.realPath(user), user, conn.RemoteAddr())
                        return private, nil
                }
        }

        logger.Printf("public key auth failed user [%v] from [%v@%v]", conn.User(), user, conn.RemoteAddr())

        return nil, nil
}

