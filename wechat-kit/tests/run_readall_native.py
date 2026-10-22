#!/usr/bin/env python3
"""Production unread driver + real NSProxy forwarding; no WeChat/user data.

Darwin: compile every variant, then require the named regression to catch it.
--sdk PATH --arch arm64|arm64e: Apple SDK object compilation ONLY (no execution).
The frozen alpha5 bytes are digest-checked; this works in a shallow CI checkout.
"""
import argparse, base64, hashlib, json, subprocess, sys, tempfile, zlib
from pathlib import Path
r=Path(__file__).resolve().parents[1]
# Frozen verbatim from 1de14e20afbb1ddd341238680473c54ef5328030.
ALPHA5_B85 = 'c-plZe{b8y^?!egvx)_xt13>r4TTh^w&f(%V#!_Pv?~PFpv9BKh9Wf{W!GyB^yijt&03)ChILud4&9m+XtEVU<1P*QVP-kWU;7Gs@7<9+l9FX7h+#<L-Me@1-tYH#kJ<f!=LhWcrRoJcI7y$y-kF)l!f|i&<@U)w7sBjveIoZl<-*0G8`ymq&LxH$JP2&JD{y>91ZH5jS-WTYOkCuqwc^`b+`qtg%HdqS@vJF&>*l7z*_;L=B8V-|wpe~ntoe4=c1;IhYu*+&@|UX5+kBhN6<Fi!s&N?ns=4D0gY1fM2`nJe{VluAE8GpZpGPzXdv%7vU&S$nU~NaR1t6H7&iP)y5%_S_{9>+FORUWSYFy^?VCcInpC^J0_$uJO2C{XdFS-rxT1Fnw765C5JG>ouegd(@JLb>{LbQN)cP!1gLz{pI6)k6TuG#0|5ysO}ptEEsiZP8Ns>=hlZ7F9I2s{2|8AJOM%`=NOqU@M$j#Q(VmmEh*nw4Pb+UCo!5o+RjE`U;gk+;3BYyXP-D?mfn4EULu#ewe)xF77Wyz9AU;Pvfxfo*g1vcW>pZkm310-y+d&+Q`UDttfZgI;GgV{-!>FCS^I!1RF^<6#Xr)TJsMx(i6V+~qz<&2uLKFR!hwvdy6Y!+3&8-Sc?|Na@7`L>aeA`NIzY3&RK44FrnZ?++Z_2eA?n84=(X;h~I<?Terq@V?R<jkBQsf;*ieF&XFV4$IHNQ*qmNEpMB>_8P;do^4s&4WCSB&@<U-HeZ}SWrT|8+KxhDF&j2R)0$!^fNP>o2Il6n=_A!htRPc~2yDs?Y;ggoT<egUmg<cq-#2%PZG37WtqQE|foE&6*#-9FvD6ZOfLaCak>)N1RoCLLl;&Idz7jOKuVkmTZ3re=C@BdSK1+<$$B3D&iQEi@Wx8$93=buy7K-5jjh1gK3Og{F*L2k4gP;fC^JNw-K5;?~pJq>&+2fDXLxE|?!=J?nedusPE<_NqQba?CYepIaTUbDSiU8?c5_DJhafDzuZAU3>j--eR%_5!G#7CMgO&pbhK=i{kbpW6DAtq(4u|zOrxUKk5`oabM7=%{I*|Ls^Eut0O2M`EyqDRf?uxK6w*jicfOMb>ki`>OHYyl8>h_mtmjLVn4B4?mNNb-Oou}z?^kHG@K$ERyI_C*!X1&{4G<kb46?Vj@?pd{p|gS6w{8gZoNm#P=J7<gcz0H=GgqRU?iqPa4|f0#~<8wp-F{ftGgllO^<QP!<%i=;UXh%sc7T;I4k!!IY+<L(Gw6yyTAMLq{*F+bjV@GrrZ#Ofpi%WM<md^ujc8wt0m;Yc67Zf@CKl4kb!Gh=CJ=Etvs^J;K`H%QW_G+w4+Jr5LNd@fe!+qF<vk{D8H8Q}mOoqRfkXd%dK3_?1N`B92}(OI9-Pg~NQ5r%l9o3ZKqn3N|G#F^-ML&t(y4zYUO8@7A6h<*TIK;K6T)v>u@+?inGICY$m4r9^br5lKBHPTA3?PGf1SqTFBMGi-In=r0%D4Zn!lbkDJOw#;!ilEB*=R8PF*?>NQAjwY0Ym;_XU8J`}Yg-BJshkIa1So$vtRN(L0xNDp{$N2$PbdvN5_N3X79hMhLpM}$rR0}#hZ7uK&m-O?S*>x7=241~my@Cl4<F)P0&Ibf*u(*3LUztfKEGfGy>&Zqcxf@WzxVq6k8X@^eRJ>T?Odb@>R_etfFPO<_kC_Pf*n|v*@1>>O!2uXsew4S)J9R1LaO8=GwDkwWc0T?IY{y~^b(X%ugFS@^-R}-sS?;_E8K|~rtCV&?2;nFwfj(kSfv-wHo&|wnI@7Di7sHUd@<~ElrSZir(;Q<0byf31ZgNGidyPr&`9hosroAA5g+|zebWUN$|3a|q%Q=JAZRdrfD)CPK9&d?b~P5^kK=CwEFM<Mh`OW=hBl@R#X3e2Ue_*C#K{f@<TDsJwluP$=pljnh#CKGK+VE&_rw|+Me%O&g#Sr96x=M8$c+O@`7IpEGz1J>tR$jssTJX2-MpBq)TG+ix)616T`0C`3u`rqUkxeFXmKdsO!mo?M_J4re0X*L&NVQ?(HqwezW(d~zJKrF+E;gPe|h)z*P}1qzWc$iNALb)|IVNGzyIXk&A<Hj^*3{^azb7**lXngR9xT*YSnt4w39u~PW`mNNP~-1A*o;rb(*Z0!m^CQ^4J>fJP$6pSa((szLe83ppH(*P(d(>ql6RHmD0KgA0euAO=ANpBEJkjPve=eim}rr${~t6%>WXq))bX_a8-GDb$J9T6RV9>9lh&>891s+)7A==p)2gJ3xxrO+D#6^;#Bk}#<kuQIJQ&=K(VHf)Htb@MzSKBl^Yn8joI#y$J6<|Y7uHX6?7sJ4=EZF9MuTY6<88fVDklVTJ`m(p4_M{{lb{Q2(uGVTKuT^K==(%dld)bY3>L}JThvr_YTVbgWvDpzIt%&UC;@L>ry%Hy>;i{v%S%cPe<=uzyH?t(T(>Gu6&Txj6`LL`;#A8NH~s3UaT4Ekf1M&?dLonA}<E_Ti?jN*^itd+u!?2>gC-}-j);|eEd(K{QjT6MS2P>W~PHZKXvvn;_s@nM|7M#$zHU%W3iye8HNG&%OM|fkc0@p9WbxMHX$dxjKta4stJ0K6o4Qp*@In_&B1QopctXGY%wr{c5lNJJ8nB4Jwhbfz+E<Im%LG6FO4(RFrCoz2IQy85K`GeCNs!n1?pSR0OFsTq3#-CP}qHl=A)KIOiI<WIfItC3kv)T82B?AQTVT5V+gV|OV_9|O@>s1<dH<qv9!-lrhS=rO*cwTrk7+haS!1UWlm!nIMkecpoA(yJEjmzm2neF#;Dz@w0vPqbd6v_)n7P5h>aFS=CN?Z*s6DS6;<h$@)2GQwUYU2Ncwb4iBq)FS+6?FQ3y&Mt93|PIlA-V=-sRL{{8pS`?t{5etYHMjhhG8u8w~D`TpM3(fc>=eso=0%;=3z_J6o>@X>dZO~hipxjntjAD*RfSRN_3Uq`RF=BlHt+9F7G{c*RcJ%0pJ9se`zC-d|3hj2ssfYFsd-uwJ|bo_%Wf4KL<Z$@8yc~m|?tXYRB1J>=ZiAPcEM4VS~`2q*n;(7r?wIblE+wqDa-sernw$SJ?i~+C>8J2L(f#`Wr#$~%(9>p=!-C_M9z7c{4Ri-~7q_V<u(DSUKstRfV1|ET!Clfrhnr3Rk#7_*`6?0&=?O>;*aaV<xXh{RCe@<}jCJ^DM;DP>%0(6BkN{GpTEt9%8<z!0Cl4psREClCpw;S}N<P!rR`%_O&Ntku<-~HF^(Wk!~egEcYZ*RKblc}<#o6g=={UiDMlLCFFYaD0Rf_Q`sBih^EU<Wpmm`ux3NF)?aNI_+1QZ(&mdQUH&ZIsgmp;q=RjES-{6VjF<QmJy6`3KHi<|pPXyXqCE{_-E(`7-Q?W#Y2w=e4e=p(Q1=^~QP+V{FkD*fEw5$@r6bS3PIR?*&Fq3u4%k5MJBH?vUiNd`)>GdEG(xOA5n@6HIT-#WIg}Xl8bI@$H=gD9R>p)ZdMlsx~MfXdarZnGU41Es%{JP#cXxa!GA3+iRsop*(OtOaP76`2C7~K-3@hX|t7Kq$=~przb3EQ~oBXk<Eo{wQ7ye47{Z-0sxF0kKsrd;)ud1sO1H=w*0fo#!{oPR;eznSJ&zr7tgLQRqGq|wffTfTCG~qim9f4IYl!niL0f1_@?5adh<wHnpRMyoOqMP(lwN>rm&Ffy1r&Ez_9d)JZ-c#QeoW~&<M0!Bq?&_MVaH%qb}I6?AVcM!uVCI$(LZvbDf<ssJrB%@Ek~1%{E06rb3ip){xwyL;Dnw$Kh$JP_}_~E8`h=l_yLpk8ztvu8dR7sX3ayOiMP8l$7afrJ;{sCixY@qvs9eb*nkWrX{~Cnk`uWYVNVzZWc^kUx=X=$3c-FP5>2Ht|~tiIEXKCTM0O|133rYJAm2)s)<d=5E#@TyzBWpMYiHmA`|#SyqqAlQTE{5T;?5gC#H`DbNEWSMp;RXhD2VHjy{+;qf&R{sF$gLcsxe^(&}n~&Bu)$aLk#lj&&nS;??+HV5bg8|1c@<agGu7jgH-4g<ZCCs?8;j^wh&`m1zbmg^KlYD%Xy6ALtM^J=j}hisec>@pgl}`&jd=A*8XO&O@P<@K{gEvI)wC(SJTZ`0RbQv|MFaMZEXj{dcYc)>I2E5pF0)jxS2$H8dH1L^P-(5E+ehiOLIx#-kpe^}NfHb#ZK$@QvXn*60Fwm9N&GGtyxpzUqh5Y|c25b@xh7LN;qO;r*DSQ)Jl|MznSB1(_dZNTR@bI7J9DnI2oCCCx7=4-(`?QR^@X#|WQca(pMpO7IiU$D(>s*Pm!ftdAh)x)<0T)vb}vs+jbwlzgCn;r=;~oI**vdAnj;m7eK#xsE4MQFyA_upQavgo0^ppi=6e;{df|=ocFbz`2aQ&(cfzByCU$dI3+DD^cM#F?WVaPFL<Ca6l=uF(!4=@$OP8^?%})GBp'
ALPHA5_SHA256 = '55d438ea8d148e6257076b95b587006bcd3f63663696c3122a57ac255fa9beb1'

def replace(source, old, new, count=1):
 assert source.count(old)==count, ('mutation anchor changed',old)
 return source.replace(old,new)

def variants(source):
 old=zlib.decompress(base64.b85decode(ALPHA5_B85))
 assert hashlib.sha256(old).hexdigest()==ALPHA5_SHA256
 return {
  'baseline':(source,None),
  'alpha5-frozen':(old.decode(),'context_proxy'),
  'mutant-no-native-context':(replace(source,'cls = NSClassFromString(@"MMContext");','cls = Nil;'),'native_context'),
  'mutant-install-default-lock':(replace(source,'Class center = WCKReadContextEntry(&entry);','Class center = (entry = NSSelectorFromString(@"defaultCenter"), NSClassFromString(@"MMServiceCenter"));'),'native_context'),
  'mutant-center-class':(replace(source,'    id center = WCKServiceCenter();',
   '    id center = WCKServiceCenter();\n    if (![center isKindOfClass:NSClassFromString(@"MMServiceCenter")]) return;'),'context_proxy'),
  'mutant-proxy-ignore-abi':(replace(source,
   '    NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];',
   '    if (class_getSuperclass(object_getClass(receiver)) == NSProxy.class) return YES;\n    NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];'),'proxy_bad_count_return'),
  'mutant-no-layout-bind':(replace(source,'WCKBindReadBar(bar); // MMTabBar only;','(void)bar; // MMTabBar only;'),'layout_first'),
  'mutant-no-size-bound':(replace(source,'[raw count] > 5000','[raw count] > 500000'),'large'),
  'mutant-no-account-check':(replace(source,'WCKService(center, @"CMessageMgr") != manager','NO',2),'proxy_replace'),
  'mutant-no-readback':(replace(source,'unsigned int after = ((unsigned int (*)(id,SEL,id))objc_msgSend)(manager, countSelector, name);','unsigned int after = 0;'),'readback'),
 }

cases=['normal','context_proxy','duplicate','replacement','layout_first','legacy','wrong_abi','nil_name','wrong_name','long_name','disabled','nonfirst','wrong_page','hidden','readback','switch_service','cancel','toggle','busy','large','no_begin','proxy_replace','context_replace','proxy_abi_change','proxy_signature_late_throw','snapshot','nil_center','nil_manager','nil_sessions','wrong_manager','wrong_sessions','nil_list','wrong_list','context_signature_throw','proxy_signature_throw']
cases += ['native_context','native_nil','native_bad_abi','native_throws']
cases += ['context_bad_'+f for f in ['return','argument','arity','self','selector','nil']]
for method,fields in [('list',['return','arity','nil']),('count',['return','argument','arity','nil']),('clear',['return','name','from','to','arity','self','selector','nil'])]:
 cases += ['proxy_bad_'+method+'_'+f for f in fields]
cases += ['throws_'+stage for stage in ['center','service','kind','list','before','clear','after']]


def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--sdk',type=Path,help='Object compile only; NOT Foundation execution')
 parser.add_argument('--arch',choices=['arm64','arm64e'],default='arm64')
 args=parser.parse_args()
 if not args.sdk and sys.platform!='darwin':
  print('requires macOS Foundation; unread model NOT executed');return 77
 source=(r/'src/WCKReadAll.m').read_text()
 rows=[]
 with tempfile.TemporaryDirectory(prefix='wck-unread-') as td:
  td=Path(td)
  for name,(body,killer) in variants(source).items():
   sp=td/(name+'.m');sp.write_text(body)
   common=['clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I'+str(r/'tests/fake-readall'),'-I'+str(r/'src')]
   if args.sdk:
    common+=['-target',args.arch+'-apple-ios15.0','-isysroot',str(args.sdk),'-Wno-incompatible-sysroot','-fmodules','-fmodules-cache-path='+str(td/'modules')]
    inputs=[sp,r/'tests/WCKReadAllModel.m'] if name=='baseline' else [sp]
    for i,src in enumerate(inputs):
     c=subprocess.run(common+['-c',str(src),'-o',str(td/(name+str(i)+'.o'))],capture_output=True,text=True,timeout=90)
     assert c.returncode==0,(name,str(src),'OBJECT COMPILE FAILED',c.stderr)
    print(name,'Apple SDK objects compiled; runtime NOT executed',flush=True)
    continue
   exe=td/name
   cmd=common+['-framework','Foundation','-framework','CoreGraphics',str(sp),str(r/'src/WCKPolicy.c'),str(r/'tests/WCKReadAllModel.m'),'-o',str(exe)]
   c=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
   assert c.returncode==0,(name,'COMPILE FAILED (not a caught mutant)',c.stderr)
   runs=[]
   for case in cases if killer is None else [killer]:
    p=subprocess.run([str(exe),case],capture_output=True,text=True,timeout=15)
    runs.append(dict(case=case,exit=p.returncode,stdout=p.stdout,stderr=p.stderr))
   # A specific compiled regression must fail: arbitrary unrelated failures do not count.
   ok=all(x['exit']==0 for x in runs) if killer is None else runs[0]['exit']!=0
   rows.append(dict(variant=name,compiled=True,expected=ok,killer=killer,cases=runs,level='Foundation + NSProxy/fake services, not UIKit/device'))
   (r/'evidence').mkdir(exist_ok=True)
   (r/'evidence/native-readall-tests.json').write_text(json.dumps(rows,indent=2))
   print(name,str(len(runs))+' cases PASS' if killer is None and ok else 'named runtime defect caught' if ok else 'FAIL',flush=True)
   assert ok,(name,runs)
 return 0

if __name__=='__main__':
 raise SystemExit(main())
