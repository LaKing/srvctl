#!/bin/bash

function wait() {
    echo 'sleep 1'
    sleep 1
}

echo "Lets test the system!"
wait
sc add-reseller alpha
sc add-reseller bravo
sc add-reseller charlie
sc add-reseller delta
sc add-reseller echo
sc add-reseller foxtrot
sc add-reseller golf
sc add-reseller hotel
sc add-reseller india
sc add-reseller juliet
sc add-reseller kilo
sc add-reseller lima
sc add-reseller mike
sc add-reseller november
sc add-reseller oscar
sc add-reseller papa
sc add-reseller quebec
wait
su alpha -c "sc add-user alpha1"
su alpha -c "sc add-user alpha2"
su alpha -c "sc add-user alpha3"
su alpha -c "sc add-user alpha4"
su alpha -c "sc add-user alpha5"
su alpha -c "sc add-user alpha6"
su alpha -c "sc add-user alpha7"
su alpha -c "sc add-user alpha8"
wait
su bravo -c "sc add-user bravo1"
su bravo -c "sc add-user bravo2"
su bravo -c "sc add-user bravo3"
su bravo -c "sc add-user bravo4"
su bravo -c "sc add-user bravo5"
su bravo -c "sc add-user bravo6"
su bravo -c "sc add-user bravo7"
su bravo -c "sc add-user bravo8"
wait
su charlie -c "sc add-user charlie1"
su charlie -c "sc add-user charlie2"
su charlie -c "sc add-user charlie3"
su charlie -c "sc add-user charlie4"
su charlie -c "sc add-user charlie5"
su charlie -c "sc add-user charlie6"
su charlie -c "sc add-user charlie7"
su charlie -c "sc add-user charlie8"
wait
su delta -c "sc add-user delta1"
su delta -c "sc add-user delta2"
su delta -c "sc add-user delta3"
su delta -c "sc add-user delta4"
su delta -c "sc add-user delta5"
su delta -c "sc add-user delta6"
su delta -c "sc add-user delta7"
su delta -c "sc add-user delta8"
wait
su alpha1 -c "sc add-ve alpha-one.ve"
su alpha2 -c "sc add-ve alpha-two.ve"
su alpha3 -c "sc add-ve alpha-three.ve"
su alpha4 -c "sc add-ve alpha-four.ve"
su alpha5 -c "sc add-ve alpha-five.ve"
su alpha6 -c "sc add-ve alpha-six.ve"
su alpha7 -c "sc add-ve alpha-seven.ve"
su alpha8 -c "sc add-ve alpha-eight.ve"
su alpha1 -c "sc add-ve alpha-nine.ve"
su alpha1 -c "sc add-ve alpha-ten.ve"
su alpha1 -c "sc add-ve alpha-eleven.ve"
su alpha1 -c "sc add-ve alpha-twelve.ve"
wait
su bravo1 -c "sc add-ve bravo-one.ve"
su bravo2 -c "sc add-ve bravo-two.ve"
su bravo3 -c "sc add-ve bravo-three.ve"
su bravo4 -c "sc add-ve bravo-four.ve"
su bravo5 -c "sc add-ve bravo-five.ve"
su bravo6 -c "sc add-ve bravo-six.ve"
su bravo7 -c "sc add-ve bravo-seven.ve"
su bravo8 -c "sc add-ve bravo-eight.ve"
su bravo1 -c "sc add-ve bravo-nine.ve"
su bravo1 -c "sc add-ve bravo-ten.ve"
su bravo1 -c "sc add-ve bravo-eleven.ve"
su bravo1 -c "sc add-ve bravo-twelve.ve"
wait
su charlie1 -c "sc add-ve charlie-one.ve"
su charlie2 -c "sc add-ve charlie-two.ve"
su charlie3 -c "sc add-ve charlie-three.ve"
su charlie4 -c "sc add-ve charlie-four.ve"
su charlie5 -c "sc add-ve charlie-five.ve"
su charlie6 -c "sc add-ve charlie-six.ve"
su charlie7 -c "sc add-ve charlie-seven.ve"
su charlie8 -c "sc add-ve charlie-eight.ve"
su charlie1 -c "sc add-ve charlie-nine.ve"
su charlie1 -c "sc add-ve charlie-ten.ve"
su charlie1 -c "sc add-ve charlie-eleven.ve"
su charlie1 -c "sc add-ve charlie-twelve.ve"
wait
su delta1 -c "sc add-ve delta-one.ve"
su delta2 -c "sc add-ve delta-two.ve"
su delta3 -c "sc add-ve delta-three.ve"
su delta4 -c "sc add-ve delta-four.ve"
su delta5 -c "sc add-ve delta-five.ve"
su delta6 -c "sc add-ve delta-six.ve"
su delta7 -c "sc add-ve delta-seven.ve"
su delta8 -c "sc add-ve delta-eight.ve"
su delta1 -c "sc add-ve delta-nine.ve"
su delta1 -c "sc add-ve delta-ten.ve"
su delta1 -c "sc add-ve delta-eleven.ve"
su delta1 -c "sc add-ve delta-twelve.ve"
wait
su alpha1 -c "sc add-ve alpha-one.d1.ve"
su alpha2 -c "sc add-ve alpha-two.d1.ve"
su alpha3 -c "sc add-ve alpha-three.d1.ve"
su alpha4 -c "sc add-ve alpha-four.d1.ve"
su alpha5 -c "sc add-ve alpha-five.d1.ve"
su alpha6 -c "sc add-ve alpha-six.d1.ve"
su alpha7 -c "sc add-ve alpha-seven.d1.ve"
su alpha8 -c "sc add-ve alpha-eight.d1.ve"
su alpha1 -c "sc add-ve alpha-nine.d1.ve"
su alpha1 -c "sc add-ve alpha-ten.d1.ve"
su alpha1 -c "sc add-ve alpha-eleven.d1.ve"
su alpha1 -c "sc add-ve alpha-twelve.d1.ve"
wait
su bravo1 -c "sc add-ve bravo-one.d1.ve"
su bravo2 -c "sc add-ve bravo-two.d1.ve"
su bravo3 -c "sc add-ve bravo-three.d1.ve"
su bravo4 -c "sc add-ve bravo-four.d1.ve"
su bravo5 -c "sc add-ve bravo-five.d1.ve"
su bravo6 -c "sc add-ve bravo-six.d1.ve"
su bravo7 -c "sc add-ve bravo-seven.d1.ve"
su bravo8 -c "sc add-ve bravo-eight.d1.ve"
su bravo1 -c "sc add-ve bravo-nine.d1.ve"
su bravo1 -c "sc add-ve bravo-ten.d1.ve"
su bravo1 -c "sc add-ve bravo-eleven.d1.ve"
su bravo1 -c "sc add-ve bravo-twelve.d1.ve"
wait
su charlie1 -c "sc add-ve charlie-one.d1.ve"
su charlie2 -c "sc add-ve charlie-two.d1.ve"
su charlie3 -c "sc add-ve charlie-three.d1.ve"
su charlie4 -c "sc add-ve charlie-four.d1.ve"
su charlie5 -c "sc add-ve charlie-five.d1.ve"
su charlie6 -c "sc add-ve charlie-six.d1.ve"
su charlie7 -c "sc add-ve charlie-seven.d1.ve"
su charlie8 -c "sc add-ve charlie-eight.d1.ve"
su charlie1 -c "sc add-ve charlie-nine.d1.ve"
su charlie1 -c "sc add-ve charlie-ten.d1.ve"
su charlie1 -c "sc add-ve charlie-eleven.d1.ve"
su charlie1 -c "sc add-ve charlie-twelve.d1.ve"
wait
su delta1 -c "sc add-ve delta-one.d1.ve"
su delta2 -c "sc add-ve delta-two.d1.ve"
su delta3 -c "sc add-ve delta-three.d1.ve"
su delta4 -c "sc add-ve delta-four.d1.ve"
su delta5 -c "sc add-ve delta-five.d1.ve"
su delta6 -c "sc add-ve delta-six.d1.ve"
su delta7 -c "sc add-ve delta-seven.d1.ve"
su delta8 -c "sc add-ve delta-eight.d1.ve"
su delta1 -c "sc add-ve delta-nine.d1.ve"
su delta1 -c "sc add-ve delta-ten.d1.ve"
su delta1 -c "sc add-ve delta-eleven.d1.ve"
su delta1 -c "sc add-ve delta-twelve.d1.ve"
wait
su alpha1 -c "sc add-ve alpha-one.d2.ve"
su alpha2 -c "sc add-ve alpha-two.d2.ve"
su alpha3 -c "sc add-ve alpha-three.d2.ve"
su alpha4 -c "sc add-ve alpha-four.d2.ve"
su alpha5 -c "sc add-ve alpha-five.d2.ve"
su alpha6 -c "sc add-ve alpha-six.d2.ve"
su alpha7 -c "sc add-ve alpha-seven.d2.ve"
su alpha8 -c "sc add-ve alpha-eight.d2.ve"
su alpha1 -c "sc add-ve alpha-nine.d2.ve"
su alpha1 -c "sc add-ve alpha-ten.d2.ve"
su alpha1 -c "sc add-ve alpha-eleven.d2.ve"
su alpha1 -c "sc add-ve alpha-twelve.d2.ve"
wait
su bravo1 -c "sc add-ve bravo-one.d2.ve"
su bravo2 -c "sc add-ve bravo-two.d2.ve"
su bravo3 -c "sc add-ve bravo-three.d2.ve"
su bravo4 -c "sc add-ve bravo-four.d2.ve"
su bravo5 -c "sc add-ve bravo-five.d2.ve"
su bravo6 -c "sc add-ve bravo-six.d2.ve"
su bravo7 -c "sc add-ve bravo-seven.d2.ve"
su bravo8 -c "sc add-ve bravo-eight.d2.ve"
su bravo1 -c "sc add-ve bravo-nine.d2.ve"
su bravo1 -c "sc add-ve bravo-ten.d2.ve"
su bravo1 -c "sc add-ve bravo-eleven.d2.ve"
su bravo1 -c "sc add-ve bravo-twelve.d2.ve"
wait
su charlie1 -c "sc add-ve charlie-one.d2.ve"
su charlie2 -c "sc add-ve charlie-two.d2.ve"
su charlie3 -c "sc add-ve charlie-three.d2.ve"
su charlie4 -c "sc add-ve charlie-four.d2.ve"
su charlie5 -c "sc add-ve charlie-five.d2.ve"
su charlie6 -c "sc add-ve charlie-six.d2.ve"
su charlie7 -c "sc add-ve charlie-seven.d2.ve"
su charlie8 -c "sc add-ve charlie-eight.d2.ve"
su charlie1 -c "sc add-ve charlie-nine.d2.ve"
su charlie1 -c "sc add-ve charlie-ten.d2.ve"
su charlie1 -c "sc add-ve charlie-eleven.d2.ve"
su charlie1 -c "sc add-ve charlie-twelve.d2.ve"
wait
su delta1 -c "sc add-ve delta-one.d2.ve"
su delta2 -c "sc add-ve delta-two.d2.ve"
su delta3 -c "sc add-ve delta-three.d2.ve"
su delta4 -c "sc add-ve delta-four.d2.ve"
su delta5 -c "sc add-ve delta-five.d2.ve"
su delta6 -c "sc add-ve delta-six.d2.ve"
su delta7 -c "sc add-ve delta-seven.d2.ve"
su delta8 -c "sc add-ve delta-eight.d2.ve"
su delta1 -c "sc add-ve delta-nine.d2.ve"
su delta1 -c "sc add-ve delta-ten.d2.ve"
su delta1 -c "sc add-ve delta-eleven.d2.ve"
su delta1 -c "sc add-ve delta-twelve.d2.ve"
wait
su alpha1 -c "sc add-ve alpha-one.d3.ve"
su alpha2 -c "sc add-ve alpha-two.d3.ve"
su alpha3 -c "sc add-ve alpha-three.d3.ve"
su alpha4 -c "sc add-ve alpha-four.d3.ve"
su alpha5 -c "sc add-ve alpha-five.d3.ve"
su alpha6 -c "sc add-ve alpha-six.d3.ve"
su alpha7 -c "sc add-ve alpha-seven.d3.ve"
su alpha8 -c "sc add-ve alpha-eight.d3.ve"
su alpha1 -c "sc add-ve alpha-nine.d3.ve"
su alpha1 -c "sc add-ve alpha-ten.d3.ve"
su alpha1 -c "sc add-ve alpha-eleven.d3.ve"
su alpha1 -c "sc add-ve alpha-twelve.d3.ve"
wait
su bravo1 -c "sc add-ve bravo-one.d3.ve"
su bravo2 -c "sc add-ve bravo-two.d3.ve"
su bravo3 -c "sc add-ve bravo-three.d3.ve"
su bravo4 -c "sc add-ve bravo-four.d3.ve"
su bravo5 -c "sc add-ve bravo-five.d3.ve"
su bravo6 -c "sc add-ve bravo-six.d3.ve"
su bravo7 -c "sc add-ve bravo-seven.d3.ve"
su bravo8 -c "sc add-ve bravo-eight.d3.ve"
su bravo1 -c "sc add-ve bravo-nine.d3.ve"
su bravo1 -c "sc add-ve bravo-ten.d3.ve"
su bravo1 -c "sc add-ve bravo-eleven.d3.ve"
su bravo1 -c "sc add-ve bravo-twelve.d3.ve"
wait
su charlie1 -c "sc add-ve charlie-one.d3.ve"
su charlie2 -c "sc add-ve charlie-two.d3.ve"
su charlie3 -c "sc add-ve charlie-three.d3.ve"
su charlie4 -c "sc add-ve charlie-four.d3.ve"
su charlie5 -c "sc add-ve charlie-five.d3.ve"
su charlie6 -c "sc add-ve charlie-six.d3.ve"
su charlie7 -c "sc add-ve charlie-seven.d3.ve"
su charlie8 -c "sc add-ve charlie-eight.d3.ve"
su charlie1 -c "sc add-ve charlie-nine.d3.ve"
su charlie1 -c "sc add-ve charlie-ten.d3.ve"
su charlie1 -c "sc add-ve charlie-eleven.d3.ve"
su charlie1 -c "sc add-ve charlie-twelve.d3.ve"
wait
su delta1 -c "sc add-ve delta-one.d3.ve"
su delta2 -c "sc add-ve delta-two.d3.ve"
su delta3 -c "sc add-ve delta-three.d3.ve"
su delta4 -c "sc add-ve delta-four.d3.ve"
su delta5 -c "sc add-ve delta-five.d3.ve"
su delta6 -c "sc add-ve delta-six.d3.ve"
su delta7 -c "sc add-ve delta-seven.d3.ve"
su delta8 -c "sc add-ve delta-eight.d3.ve"
su delta1 -c "sc add-ve delta-nine.d3.ve"
su delta1 -c "sc add-ve delta-ten.d3.ve"
su delta1 -c "sc add-ve delta-eleven.d3.ve"
su delta1 -c "sc add-ve delta-twelve.d3.ve"
wait
su alpha1 -c "sc add-ve alpha-one.d4.ve"
su alpha2 -c "sc add-ve alpha-two.d4.ve"
su alpha3 -c "sc add-ve alpha-three.d4.ve"
su alpha4 -c "sc add-ve alpha-four.d4.ve"
su alpha5 -c "sc add-ve alpha-five.d4.ve"
su alpha6 -c "sc add-ve alpha-six.d4.ve"
su alpha7 -c "sc add-ve alpha-seven.d4.ve"
su alpha8 -c "sc add-ve alpha-eight.d4.ve"
su alpha1 -c "sc add-ve alpha-nine.d4.ve"
su alpha1 -c "sc add-ve alpha-ten.d4.ve"
su alpha1 -c "sc add-ve alpha-eleven.d4.ve"
su alpha1 -c "sc add-ve alpha-twelve.d4.ve"
wait
su bravo1 -c "sc add-ve bravo-one.d4.ve"
su bravo2 -c "sc add-ve bravo-two.d4.ve"
su bravo3 -c "sc add-ve bravo-three.d4.ve"
su bravo4 -c "sc add-ve bravo-four.d4.ve"
su bravo5 -c "sc add-ve bravo-five.d4.ve"
su bravo6 -c "sc add-ve bravo-six.d4.ve"
su bravo7 -c "sc add-ve bravo-seven.d4.ve"
su bravo8 -c "sc add-ve bravo-eight.d4.ve"
su bravo1 -c "sc add-ve bravo-nine.d4.ve"
su bravo1 -c "sc add-ve bravo-ten.d4.ve"
su bravo1 -c "sc add-ve bravo-eleven.d4.ve"
su bravo1 -c "sc add-ve bravo-twelve.d4.ve"
wait
su charlie1 -c "sc add-ve charlie-one.d4.ve"
su charlie2 -c "sc add-ve charlie-two.d4.ve"
su charlie3 -c "sc add-ve charlie-three.d4.ve"
su charlie4 -c "sc add-ve charlie-four.d4.ve"
su charlie5 -c "sc add-ve charlie-five.d4.ve"
su charlie6 -c "sc add-ve charlie-six.d4.ve"
su charlie7 -c "sc add-ve charlie-seven.d4.ve"
su charlie8 -c "sc add-ve charlie-eight.d4.ve"
su charlie1 -c "sc add-ve charlie-nine.d4.ve"
su charlie1 -c "sc add-ve charlie-ten.d4.ve"
su charlie1 -c "sc add-ve charlie-eleven.d4.ve"
su charlie1 -c "sc add-ve charlie-twelve.d4.ve"
wait
su delta1 -c "sc add-ve delta-one.d4.ve"
su delta2 -c "sc add-ve delta-two.d4.ve"
su delta3 -c "sc add-ve delta-three.d4.ve"
su delta4 -c "sc add-ve delta-four.d4.ve"
su delta5 -c "sc add-ve delta-five.d4.ve"
su delta6 -c "sc add-ve delta-six.d4.ve"
su delta7 -c "sc add-ve delta-seven.d4.ve"
su delta8 -c "sc add-ve delta-eight.d4.ve"
su delta1 -c "sc add-ve delta-nine.d4.ve"
su delta1 -c "sc add-ve delta-ten.d4.ve"
su delta1 -c "sc add-ve delta-eleven.d4.ve"
su delta1 -c "sc add-ve delta-twelve.d4.ve"

echo "srvctl rocks!"
