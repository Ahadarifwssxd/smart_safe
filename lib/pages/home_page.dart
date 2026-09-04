import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../models/models.dart';
import 'alert_history_page.dart';
import 'notification_page.dart';
import 'safe_route_page.dart';
import 'crash_detection_page.dart';

class HomePage extends StatefulWidget {
  final VoidCallback onSOSTap;
  const HomePage({super.key, required this.onSOSTap});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  String _time=''; bool _shaking=false; late Timer _clock;
  @override void initState(){super.initState();_tick();_clock=Timer.periodic(const Duration(seconds:30),(_)=>_tick());}
  void _tick(){final n=DateTime.now();if(mounted)setState(()=>_time='${n.hour.toString().padLeft(2,'0')}:${n.minute.toString().padLeft(2,'0')}');}
  void _shake() async{setState(()=>_shaking=true);await Future.delayed(const Duration(milliseconds:500));if(mounted)setState(()=>_shaking=false);}
  @override void dispose(){_clock.cancel();super.dispose();}

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:C.bg,
    body:Stack(children:[
      const DotGrid(),
      SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:20,vertical:12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Text(_time,style:TextStyle(color:C.textPrimary,fontSize:13,fontWeight:FontWeight.w700)),
          Row(children:[
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertHistoryPage())),
              child: Icon(Icons.history_rounded, color: C.textPrimary, size: 20),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
              child: Icon(Icons.notifications_none_rounded, color: C.textPrimary, size: 20),
            ),
          ]),
        ]),
        const SizedBox(height:18),
        SlideUpFade(delay:const Duration(milliseconds:50),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Good evening,',style:TextStyle(color:C.textMuted,fontSize:12)),
          Text('Amina Khan',style:TextStyle(color:C.textPrimary,fontSize:22,fontWeight:FontWeight.w800)),
        ])),
        const SizedBox(height:24),
        Center(child:SlideUpFade(delay:const Duration(milliseconds:100),child:Column(children:[
          Text('EMERGENCY BUTTON',style:TextStyle(color:C.textMuted,fontSize:10,letterSpacing:1.4)),
          const SizedBox(height:18),
          PulseRing(size:110,color:C.accent,rings:3,child:PulseSOSButton(onTap:widget.onSOSTap)),
          const SizedBox(height:12),
          Text('Tap  ·  Shake phone  ·  Volume buttons',style:TextStyle(color:C.textMuted,fontSize:10)),
        ]))),
        const SizedBox(height:26),
        SlideUpFade(delay:const Duration(milliseconds:180),child:GridView.count(
          crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
          crossAxisSpacing:8,mainAxisSpacing:8,childAspectRatio:2.4,
          children:[
            const _FCard(icon:'📍',title:'GPS Active',   sub:'Live sharing on'),
            _FCard(icon:'🚑',title:'Crash Detect', sub:'Auto-alert ON', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CrashDetectionPage(onCrashDetected: () {})))),
            _FCard(icon:'🛡️',title:'Safe Route',   sub:'Tap to plan', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SafeRoutePage()))),
            const _FCard(icon:'📱',title:'SMS Backup',   sub:'No internet OK'),
          ])),
        const SizedBox(height:22),
        SlideUpFade(delay:const Duration(milliseconds:250),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const SecHeader('Trusted Circle'),
          Row(children:[
            ...demoContacts.map((c)=>Padding(padding:const EdgeInsets.only(right:10),
              child:CircleAvatar(radius:20,backgroundColor:c.color,child:Text(c.initial,style:TextStyle(color:C.textPrimary,fontSize:13,fontWeight:FontWeight.w700))))),
            Container(width:40,height:40,decoration:BoxDecoration(shape:BoxShape.circle,color:C.bg2,border:Border.all(color:C.textDim,width:1.5)),
              child:Icon(Icons.add,color:C.textMuted,size:18)),
          ]),
        ])),
        const SizedBox(height:18),
        SlideUpFade(delay:const Duration(milliseconds:310),child:GestureDetector(onTap:_shake,
          child:DCard(child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
            AnimatedSlide(offset:_shaking?const Offset(.05,0):Offset.zero,duration:const Duration(milliseconds:80),
              child:const Text('📱',style:TextStyle(fontSize:22))),
            const SizedBox(width:10),
            Text('Shake phone 3× to trigger silently',style:TextStyle(color:C.textMuted,fontSize:12)),
          ])))),
        const SizedBox(height:18),
        SlideUpFade(delay:const Duration(milliseconds:370),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const SecHeader('Safety Tips'),
          _TipRow(color:C.accent,  icon:Icons.shield_rounded,     tip:'Enable Silent SOS for discreet alerts'),
          const SizedBox(height:8),
          _TipRow(color:C.warning, icon:Icons.car_crash_rounded,  tip:'Keep crash detection ON while driving'),
          const SizedBox(height:8),
          _TipRow(color:C.success, icon:Icons.route_rounded,      tip:'Check Safe Route before night travel'),
        ])),
        const SizedBox(height:20),
      ]))),
    ]));
}
class _FCard extends StatelessWidget {
  final String icon,title,sub;
  final VoidCallback? onTap;
  const _FCard({required this.icon,required this.title,required this.sub, this.onTap});
  @override Widget build(BuildContext context)=>GestureDetector(
    onTap: onTap,
    child: Container(
      padding:const EdgeInsets.all(10),
      decoration:BoxDecoration(color:C.bg2,borderRadius:BorderRadius.circular(12),border:Border.all(color:C.textPrimary.withOpacity(.06))),
      child:Row(children:[Text(icon,style:const TextStyle(fontSize:18)),const SizedBox(width:8),
        Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
          Text(title,style:TextStyle(color:C.textPrimary,fontSize:11,fontWeight:FontWeight.w700)),
          Text(sub,style:TextStyle(color:C.textMuted,fontSize:10), overflow: TextOverflow.ellipsis),
        ]))])));
}
class _TipRow extends StatelessWidget {
  final Color color;final IconData icon;final String tip;
  const _TipRow({required this.color,required this.icon,required this.tip});
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.all(12),
    decoration:BoxDecoration(color:C.bg2,borderRadius:BorderRadius.circular(10),border:Border(left:BorderSide(color:color,width:3))),
    child:Row(children:[Icon(icon,color:color,size:18),const SizedBox(width:10),Expanded(child:Text(tip,style:TextStyle(color:C.textMuted,fontSize:11)))]));
}