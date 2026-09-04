import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class AlertPage extends StatefulWidget {
  final VoidCallback onCancel;
  const AlertPage({super.key, required this.onCancel});
  @override State<AlertPage> createState() => _AlertPageState();
}
class _AlertPageState extends State<AlertPage> with SingleTickerProviderStateMixin {
  int _cd=30; Timer? _t; bool _ambDone=false,_policeOn=false;
  late AnimationController _arc;
  @override void initState(){
    super.initState();
    _arc=AnimationController(vsync:this,duration:const Duration(seconds:30))..forward();
    _t=Timer.periodic(const Duration(seconds:1),(_){if(!mounted)return;setState((){if(_cd>0)_cd--;if(_cd==27)_ambDone=true;if(_cd==25)_policeOn=true;});});
  }
  @override void dispose(){_t?.cancel();_arc.dispose();super.dispose();}

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:C.bg,
    body:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:20,vertical:16),child:Column(children:[
      const SizedBox(height:10),
      PulseRing(size:120,color:C.accent,rings:3,child:Container(width:100,height:100,
        decoration:BoxDecoration(shape:BoxShape.circle,color:C.accent,boxShadow:const [BoxShadow(color:Color(0x66E63946),blurRadius:30,spreadRadius:8)]),
        child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          Text('SOS',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900,color:C.textPrimary)),
          Text('ACTIVE',style:TextStyle(fontSize:9,color:C.textPrimary.withOpacity(0.7))),
        ]))),
      const SizedBox(height:22),
      Text('ALERT SENT!',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800,color:C.accent,letterSpacing:1.5)),
      const SizedBox(height:4),
      Text('Help is on the way · Stay calm',style:TextStyle(color:C.textMuted,fontSize:13)),
      const SizedBox(height:22),
      _Step(color:C.accent,done:true,text:'GPS captured — Saddar, Karachi'),
      const SizedBox(height:6),
      _Step(color:C.accent,done:true,text:'4 contacts notified via SMS + app'),
      const SizedBox(height:6),
      _Step(color:_ambDone?C.accent:C.warning,done:_ambDone,spinning:!_ambDone,text:_ambDone?'1122 ambulance called — ETA 8 min':'Dialling 1122 ambulance...'),
      const SizedBox(height:6),
      AnimatedOpacity(opacity:_policeOn?1:.3,duration:const Duration(milliseconds:400),
        child:_Step(color:C.accent,done:false,text:'Police alert queued (15)')),
      const SizedBox(height:26),
      SizedBox(width:80,height:80,child:Stack(alignment:Alignment.center,children:[
        AnimatedBuilder(animation:_arc,builder:(_,__)=>SizedBox(width:80,height:80,
          child:CircularProgressIndicator(value:1-_arc.value,strokeWidth:6,color:C.accent,backgroundColor:C.border))),
        Text('$_cd',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800,color:C.accent)),
      ])),
      const SizedBox(height:6),
      Text('Cancels in $_cd seconds if you\'re safe',style:TextStyle(color:C.textMuted,fontSize:11)),
      const SizedBox(height:20),
      DCard(borderColor:C.accent,child:Row(children:[
        Icon(Icons.location_on_rounded,color:C.accent,size:20),const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Live location sharing',style:TextStyle(color:C.textPrimary,fontSize:13,fontWeight:FontWeight.w600)),
          Text('Saddar, Karachi · Every 3s',style:TextStyle(color:C.textMuted,fontSize:11)),
        ])),
        const WaveBars(),
      ])),
      const SizedBox(height:12),
      GestureDetector(onTap:widget.onCancel,
        child:DCard(child:Text('✅  I AM SAFE — Cancel Alert',textAlign:TextAlign.center,
          style:TextStyle(color:C.textMuted,fontSize:14,fontWeight:FontWeight.w600)))),
      const SizedBox(height:16),
    ]))));
}
class _Step extends StatelessWidget {
  final Color color;final bool done,spinning;final String text;
  const _Step({required this.color,required this.done,this.spinning=false,required this.text});
  @override Widget build(BuildContext context)=>DCard(padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
    child:Row(children:[
      spinning?SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:color))
        :Container(width:16,height:16,decoration:BoxDecoration(shape:BoxShape.circle,color:color),
          child:done?Icon(Icons.check,size:10,color:C.textPrimary):null),
      const SizedBox(width:10),
      Expanded(child:Text(text,style:TextStyle(color:C.textMuted,fontSize:12))),
    ]));
}