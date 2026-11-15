-- srvctl (modules/opendkim/conf/signing-policy.lua) — OpenDKIM SetupPolicyScript.
--
-- Installed by regenerate_opendkim_conf (libs/opendkimlib.sh) as
-- /etc/opendkim/srvctl-signing-policy.lua and enabled only on a Lua-capable
-- opendkim whose every smtpd listener passes {auth_authen} to the milter.
-- The SigningTable is then empty: every signature comes from here.
--
-- A message is signed for its header From domain D only when the sender is
-- entitled to D:
--   - SMTP AUTH sessions ({auth_authen} set): the login's domain must be D
--     and D must have a key (SignableDomains); the client IP is ignored;
--   - everything else: "<client ip>/D" must be in EntitledSigners (container
--     IPs for what they own, 127.0.0.1 / ::1 for the host's own domains),
--     generated from the datastore by lib/entitlement.js.
-- Anything else is not signed but verified, like inbound mail, and the
-- reason is logged. Not signed rather than rejected: mail flow stays
-- fail-open, and the receiver applies D's own DMARC policy.
-- Any error ends in verify (no signature), never in a signature.
-- The selector rule is the one of opendkim.js / lib/entitlement.js.

local function policy()
    local fd = odkim.get_fromdomain(ctx)
    if fd == nil or fd == "" then
        return false, "no From domain"
    end
    fd = string.lower(fd)

    local user = odkim.get_mtasymbol(ctx, "{auth_authen}")
    if user ~= nil and user ~= "" then
        local ud = string.match(string.lower(user), "@([^@]+)$")
        if ud == nil or ud ~= fd then
            return false, "login " .. user .. " is not entitled to " .. fd
        end
        local db = odkim.db_open("/var/opendkim/SignableDomains", true)
        local ok = odkim.db_check(db, fd)
        odkim.db_close(db)
        if ok ~= 1 and ok ~= true then
            return false, fd .. " has no key"
        end
        return true, fd
    end

    local ip = odkim.get_clientip(ctx)
    if ip == nil or ip == "" then
        return false, "no client IP"
    end
    local db = odkim.db_open("/var/opendkim/EntitledSigners", true)
    local ok = odkim.db_check(db, ip .. "/" .. fd)
    odkim.db_close(db)
    if ok ~= 1 and ok ~= true then
        return false, ip .. " is not entitled to " .. fd
    end
    return true, fd
end

local done, entitled, what = pcall(policy)
if done and entitled then
    local sel = "default"
    if string.sub(what, 1, 5) == "mail." then
        sel = "mail"
    end
    local signed, why = pcall(odkim.sign, ctx, sel .. "._domainkey." .. what)
    if not signed then
        pcall(odkim.log, ctx, "srvctl: not signing " .. what .. ": " .. tostring(why))
        odkim.verify(ctx)
    end
else
    if not done then
        what = "policy error: " .. tostring(entitled)
    end
    pcall(odkim.log, ctx, "srvctl: not signing: " .. tostring(what))
    odkim.verify(ctx)
end
