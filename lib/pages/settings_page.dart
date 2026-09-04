import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState()=>_SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage>{
  bool _shake=true,_crash=true,_sms=true,_silent=false,_night=true,_police=false,_loc=true;

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:C.bg,
    body:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:20,vertical:16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Settings',style:TextStyle(color:C.textPrimary,fontSize:22,fontWeight:FontWeight.w800)),
      const SizedBox(height:20),
      SlideUpFade(child:DCard(borderColor:C.accent,child:Row(children:[
        Container(width:54,height:54,decoration:BoxDecoration(shape:BoxShape.circle,color:C.bg3,border:Border.all(color:C.accent,width:2)),
          child:Center(child:Text('A',style:TextStyle(color:C.textPrimary,fontSize:22,fontWeight:FontWeight.w800)))),
        const SizedBox(width:14),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Amina Khan',style:TextStyle(color:C.textPrimary,fontSize:16,fontWeight:FontWeight.w700)),
          Text('amina@email.com',style:TextStyle(color:C.textMuted,fontSize:12)),
          Text('+92 300 1234567',style:TextStyle(color:C.textMuted,fontSize:12)),
        ])),
        Icon(Icons.edit_rounded,color:C.textMuted,size:18),
      ]))),
      const SizedBox(height:22),
      SlideUpFade(delay:const Duration(milliseconds:80),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const SecHeader('Safety features'),
        DCard(child:Column(children:[
          TRow(label:'Shake to SOS',       sub:'Shake 3× to trigger silently',     value:_shake,  onChanged:(v)=>setState(()=>_shake=v)),
          Divider(color:C.border,height:1),
          TRow(label:'Crash detection',    sub:'Auto-detect vehicle accidents',     value:_crash,  onChanged:(v)=>setState(()=>_crash=v)),
          Divider(color:C.border,height:1),
          TRow(label:'SMS offline backup', sub:'Works without internet',            value:_sms,    onChanged:(v)=>setState(()=>_sms=v)),
          Divider(color:C.border,height:1),
          TRow(label:'Silent SOS mode',    sub:'No sound or screen flash',          value:_silent, onChanged:(v)=>setState(()=>_silent=v)),
          Divider(color:C.border,height:1),
          TRow(label:'Night travel alerts',sub:'Extra warnings after 10 PM',        value:_night,  onChanged:(v)=>setState(()=>_night=v)),
          Divider(color:C.border,height:1),
          TRow(label:'Auto-call police',   sub:'Dial 15 if no response in 60s',     value:_police, onChanged:(v)=>setState(()=>_police=v)),
          Divider(color:C.border,height:1),
          TRow(label:'Background location',sub:'Track GPS always-on',               value:_loc,    onChanged:(v)=>setState(()=>_loc=v)),
        ])),
      ])),
      const SizedBox(height:20),
      SlideUpFade(delay:const Duration(milliseconds:160),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const SecHeader('Emergency numbers'),
        EmerBtn(icon:Icons.local_hospital_rounded, label:'Ambulance — 1122', color:C.accent,   onTap:(){}),
        const SizedBox(height:8),
        EmerBtn(icon:Icons.local_police_rounded,   label:'Police — 15',      color:C.accent,  onTap:(){}),
        const SizedBox(height:8),
        EmerBtn(icon:Icons.fire_truck_rounded,     label:'Rescue — 1122',    color:C.warning, onTap:(){}),
      ])),
      const SizedBox(height:20),
      SlideUpFade(delay:const Duration(milliseconds:220),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const SecHeader('About'),
        DCard(child:Column(children:[
          const _IRow('App version','1.0.0'),
          Divider(color:C.border,height:1),
          const _IRow('Data storage','All local — never shared'),
          Divider(color:C.border,height:1),
          const _IRow('Emergency protocol','Pakistan standard'),
          Divider(color:C.border,height:1),
          GestureDetector(onTap:(){},child:Padding(padding:const EdgeInsets.symmetric(vertical:12),
            child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
              Text('Privacy policy',style:TextStyle(color:C.textMuted,fontSize:13)),
              Icon(Icons.arrow_forward_ios_rounded,color:C.textMuted,size:14),
            ]))),
        ])),
      ])),
      const SizedBox(height:20),
      SlideUpFade(delay:const Duration(milliseconds:280),child:GestureDetector(onTap:(){},
        child:DCard(borderColor:C.accent,child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          Icon(Icons.logout_rounded,color:C.accent,size:18),const SizedBox(width:8),
          Text('Sign out',style:TextStyle(color:C.accent,fontSize:14,fontWeight:FontWeight.w600)),
        ])))),
      const SizedBox(height:24),
    ]))));
}
class _IRow extends StatelessWidget {
  final String l,v;const _IRow(this.l,this.v);
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:12),
    child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      Text(l,style:TextStyle(color:C.textMuted,fontSize:13)),
      Text(v,style:TextStyle(color:C.textMuted,fontSize:13)),
    ]));
}