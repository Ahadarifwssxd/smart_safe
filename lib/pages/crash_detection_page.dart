import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class CrashDetectionPage extends StatefulWidget {
  final VoidCallback onCrashDetected;
  const CrashDetectionPage({super.key, required this.onCrashDetected});
  @override State<CrashDetectionPage> createState()=>_CrashDetectionPageState();
}
class _CrashDetectionPageState extends State<CrashDetectionPage> with TickerProviderStateMixin {
  bool _on=true;
  String _sens='Medium';
  double _level=.22;
  bool _crashed=false;
  int _cd=10;
  Timer? _impT,_cdT;
  final _steps=[
    {'icon':Icons.sensors_rounded,       'color':C.accent,   'label':'Impact detected instantly'},
    {'icon':Icons.timer_rounded,         'color':C.warning, 'label':'10-sec cancel window opens'},
    {'icon':Icons.location_on_rounded,   'color':C.accent,  'label':'GPS sent to all contacts'},
    {'icon':Icons.local_hospital_rounded,'color':C.success, 'label':'1122 ambulance auto-dialled'},
  ];
  @override void initState(){
    super.initState();
    _impT=Timer.periodic(const Duration(milliseconds:600),(_){if(mounted&&!_crashed)setState(()=>_level=.1+Random().nextDouble()*.3);});
  }
  void _crash(){
    setState((){_crashed=true;_level=1.0;_cd=10;});
    _cdT=Timer.periodic(const Duration(seconds:1),(_){
      if(!mounted){_cdT?.cancel();return;}
      setState((){if(_cd>0) {
        _cd--;
      } else{_cdT?.cancel();widget.onCrashDetected();}});
    });
  }
  void _cancel(){_cdT?.cancel();setState((){_crashed=false;_level=.22;});}
  @override void dispose(){_impT?.cancel();_cdT?.cancel();super.dispose();}

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:C.bg,
    body:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:20,vertical:16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Row(children:[
          GestureDetector(onTap:()=>Navigator.pop(context),child:Icon(Icons.arrow_back_ios_new_rounded,color:C.textPrimary,size:20)),
          const SizedBox(width:12),
          Text('Crash Detection',style:TextStyle(color:C.textPrimary,fontSize:20,fontWeight:FontWeight.w800)),
        ]),
        Switch(value:_on,onChanged:(v)=>setState(()=>_on=v)),
      ]),
      Text(_on?'Accelerometer monitoring active':'Detection is OFF',style:TextStyle(color:_on?C.accent:C.textMuted,fontSize:12)),
      const SizedBox(height:22),
      Center(child:_crashed
        ?PulseRing(size:110,color:C.accent,rings:3,child:Container(width:90,height:90,
          decoration:BoxDecoration(shape:BoxShape.circle,color:C.accent,boxShadow:const [BoxShadow(color:Color(0x66E63946),blurRadius:25,spreadRadius:6)]),
          child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            Icon(Icons.car_crash_rounded,color:C.textPrimary,size:30),
            Text('CRASH!',style:TextStyle(color:C.textPrimary,fontSize:11,fontWeight:FontWeight.w800)),
          ])))
        :Container(width:100,height:100,
          decoration:BoxDecoration(shape:BoxShape.circle,color:_on?C.warning.withOpacity(.12):C.bg2,
            border:Border.all(color:_on?C.warning.withOpacity(.4):C.textDim,width:2)),
          child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            Icon(Icons.car_crash_rounded,color:_on?C.warning:C.textMuted,size:34),
            const SizedBox(height:4),
            Text(_on?'MONITORING':'PAUSED',style:TextStyle(color:_on?C.warning:C.textMuted,fontSize:9,fontWeight:FontWeight.w700)),
          ]))),
      if(_crashed)...[
        const SizedBox(height:16),
        Center(child:Column(children:[
          Text('CRASH DETECTED!',style:TextStyle(color:C.accent,fontSize:18,fontWeight:FontWeight.w800,letterSpacing:1)),
          const SizedBox(height:4),
          Text('Sending alert in $_cd seconds...',style:TextStyle(color:C.textMuted,fontSize:12)),
          const SizedBox(height:12),
          SizedBox(width:70,height:70,child:Stack(alignment:Alignment.center,children:[
            CircularProgressIndicator(value:_cd/10,strokeWidth:6,color:C.accent,backgroundColor:C.border),
            Text('$_cd',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800,color:C.accent)),
          ])),
          const SizedBox(height:12),
          GestureDetector(onTap:_cancel,child:Container(
            padding:const EdgeInsets.symmetric(horizontal:28,vertical:12),
            decoration:BoxDecoration(color:C.success,borderRadius:BorderRadius.circular(30)),
            child:Text('I\'M OK — Cancel',style:TextStyle(color:C.textPrimary,fontSize:14,fontWeight:FontWeight.w700)))),
        ])),
      ],
      if(!_crashed)...[
        const SizedBox(height:22),
        const SecHeader('Live accelerometer'),
        DCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            Text('Impact level',style:TextStyle(color:C.textMuted,fontSize:11)),
            Text(_level<.4?'Normal':_level<.7?'Elevated':'HIGH!',
              style:TextStyle(color:_level<.4?C.success:_level<.7?C.warning:C.accent,fontSize:11,fontWeight:FontWeight.w700)),
          ]),
          const SizedBox(height:8),
          ClipRRect(borderRadius:BorderRadius.circular(4),child:AnimatedContainer(
            duration:const Duration(milliseconds:300),height:8,width:double.infinity,
            child:LinearProgressIndicator(value:_level,backgroundColor:C.border,
              valueColor:AlwaysStoppedAnimation(_level<.4?C.success:_level<.7?C.warning:C.accent)))),
        ])),
        const SizedBox(height:14),
      ],
      const SecHeader('Sensitivity'),
      Row(children:['Low','Medium','High'].map((s){final sel=s==_sens;
        return Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:3),
          child:GestureDetector(onTap:()=>setState(()=>_sens=s),
            child:AnimatedContainer(duration:const Duration(milliseconds:200),
              padding:const EdgeInsets.symmetric(vertical:10),
              decoration:BoxDecoration(color:sel?C.accent:C.bg2,borderRadius:BorderRadius.circular(10),border:Border.all(color:sel?C.accent:C.textDim)),
              child:Text(s,textAlign:TextAlign.center,style:TextStyle(color:sel?C.textPrimary:C.textMuted,fontSize:12,fontWeight:sel?FontWeight.w700:FontWeight.normal))))));
      }).toList()),
      const SizedBox(height:20),
      const SecHeader('What happens on crash'),
      ..._steps.asMap().entries.map((e)=>SlideUpFade(delay:Duration(milliseconds:80+e.key*60),
        child:Padding(padding:const EdgeInsets.only(bottom:8),child:DCard(padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
          child:Row(children:[
            Container(width:28,height:28,decoration:BoxDecoration(shape:BoxShape.circle,color:e.value['color'] as Color),
              child:Center(child:Text('${e.key+1}',style:TextStyle(color:C.textPrimary,fontSize:11,fontWeight:FontWeight.w800)))),
            const SizedBox(width:12),
            Icon(e.value['icon'] as IconData,color:e.value['color'] as Color,size:18),
            const SizedBox(width:10),
            Text(e.value['label'] as String,style:TextStyle(color:C.textMuted,fontSize:13)),
          ]))))),
      const SizedBox(height:16),
      if(!_crashed) BigBtn(label:'Test Crash Detection',color:C.warning,icon:Icons.science_rounded,onTap:_crash),
      const SizedBox(height:20),
    ]))));
}