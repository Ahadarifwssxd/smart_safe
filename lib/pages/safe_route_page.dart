import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../models/models.dart';

class SafeRoutePage extends StatefulWidget {
  const SafeRoutePage({super.key});
  @override State<SafeRoutePage> createState()=>_SafeRoutePageState();
}
class _SafeRoutePageState extends State<SafeRoutePage>{
  String _sel='Now';
  final _times=['Now','6 PM','9 PM','11 PM','1 AM'];

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:C.bg,
    body:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:20,vertical:16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Row(children:[
          GestureDetector(onTap:()=>Navigator.pop(context),child:Icon(Icons.arrow_back_ios_new_rounded,color:C.textPrimary,size:20)),
          const SizedBox(width:12),
          Text('Safe Route',style:TextStyle(color:C.textPrimary,fontSize:22,fontWeight:FontWeight.w800)),
        ]),
        Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
          decoration:BoxDecoration(color:C.success.withOpacity(.15),borderRadius:BorderRadius.circular(20),border:Border.all(color:C.success.withOpacity(.4))),
          child:Text('LIVE',style:TextStyle(color:C.success,fontSize:10,fontWeight:FontWeight.w700))),
      ]),
      const SizedBox(height:16),
      const SecHeader('Travel time'),
      SizedBox(height:36,child:ListView.separated(
        scrollDirection:Axis.horizontal,itemCount:_times.length,
        separatorBuilder:(_,__)=>const SizedBox(width:8),
        itemBuilder:(_,i){final t=_times[i];final s=t==_sel;
          return GestureDetector(onTap:()=>setState(()=>_sel=t),
            child:AnimatedContainer(duration:const Duration(milliseconds:200),
              padding:const EdgeInsets.symmetric(horizontal:16),
              decoration:BoxDecoration(color:s?C.accent:C.bg2,borderRadius:BorderRadius.circular(20),border:Border.all(color:s?C.accent:C.textDim)),
              child:Center(child:Text(t,style:TextStyle(color:s?C.textPrimary:C.textMuted,fontSize:12,fontWeight:s?FontWeight.w700:FontWeight.normal)))));})),
      const SizedBox(height:18),
      SlideUpFade(child:Container(height:180,
        decoration:BoxDecoration(color:const Color(0xFF081413),borderRadius:BorderRadius.circular(16),border:Border.all(color:C.accent.withOpacity(.3),width:1.5)),
        child:ClipRRect(borderRadius:BorderRadius.circular(14),child:Stack(children:[
          CustomPaint(painter:GridPainter(),size:const Size(double.infinity,180)),
          CustomPaint(painter:_RoutePainter(),size:const Size(double.infinity,180)),
          Positioned(left:28,top:36,child:_Pin(color:C.accent,label:'Start')),
          Positioned(right:28,bottom:28,child:_Pin(color:C.accent,label:'End')),
        ])))),
      const SizedBox(height:8),
      Row(children:[
        _Leg(color:C.success,label:'Safe'),const SizedBox(width:16),
        _Leg(color:C.warning,label:'Caution'),const SizedBox(width:16),
        _Leg(color:C.accent,label:'Avoid'),
      ]),
      const SizedBox(height:18),
      const SecHeader('Route options'),
      ...demoRoutes.asMap().entries.map((e)=>SlideUpFade(delay:Duration(milliseconds:80+e.key*60),
        child:Padding(padding:const EdgeInsets.only(bottom:10),child:_RouteCard(route:e.value,rec:e.key==0)))),
      const SizedBox(height:8),
      DCard(borderColor:C.accent,child:Row(children:[
        Container(width:36,height:36,decoration:BoxDecoration(color:C.accent.withOpacity(.15),borderRadius:BorderRadius.circular(8)),
          child:Center(child:Icon(Icons.nightlight_round,color:C.accent,size:18))),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Night travel alert',style:TextStyle(color:C.textPrimary,fontSize:13,fontWeight:FontWeight.w600)),
          Text('Lyari area unsafe after 10 PM. Use recommended route.',style:TextStyle(color:C.textMuted,fontSize:11)),
        ])),
      ])),
      const SizedBox(height:14),
      BigBtn(label:'Start Safe Navigation',color:C.success,icon:Icons.navigation_rounded,onTap:(){}),
      const SizedBox(height:20),
    ]))));
}
class _RouteCard extends StatelessWidget {
  final RouteSegment route;final bool rec;
  const _RouteCard({required this.route,required this.rec});
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.all(14),
    decoration:BoxDecoration(color:C.bg2,borderRadius:BorderRadius.circular(12),
      border:Border.all(color:rec?route.color.withOpacity(.5):C.textPrimary.withOpacity(.06),width:rec?1.5:1)),
    child:Row(children:[
      Container(width:5,height:48,decoration:BoxDecoration(color:route.color,borderRadius:BorderRadius.circular(3))),
      const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Text(route.name,style:TextStyle(color:C.textPrimary,fontSize:13,fontWeight:FontWeight.w700)),
          if(rec)...[const SizedBox(width:8),Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
            decoration:BoxDecoration(color:C.success.withOpacity(.2),borderRadius:BorderRadius.circular(4)),
            child:Text('Recommended',style:TextStyle(color:C.success,fontSize:9,fontWeight:FontWeight.w700)))],
        ]),
        const SizedBox(height:4),
        Text(route.detail,style:TextStyle(color:C.textMuted,fontSize:11)),
      ])),
      Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
        Text('${route.minutes} min',style:TextStyle(color:C.textPrimary,fontSize:14,fontWeight:FontWeight.w700)),
        const SizedBox(height:4),
        StatusChip(label:route.levelText,color:route.color),
      ]),
    ]));
}
class _Leg extends StatelessWidget {
  final Color color;final String label;
  const _Leg({required this.color,required this.label});
  @override Widget build(BuildContext context)=>Row(children:[Container(width:10,height:10,decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(2))),const SizedBox(width:5),Text(label,style:TextStyle(color:C.textMuted,fontSize:11))]);
}
class _Pin extends StatelessWidget {
  final Color color;final String label;
  const _Pin({required this.color,required this.label});
  @override Widget build(BuildContext context)=>Column(children:[
    Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(4)),child:Text(label,style:TextStyle(color:C.textPrimary,fontSize:9,fontWeight:FontWeight.w700))),
    const SizedBox(height:2),Container(width:8,height:8,decoration:BoxDecoration(shape:BoxShape.circle,color:color)),
  ]);
}
class _RoutePainter extends CustomPainter {
  @override void paint(Canvas c,Size s){
    final safe=Paint()..color=C.success.withOpacity(.7)..strokeWidth=3..style=PaintingStyle.stroke..strokeCap=StrokeCap.round;
    final caution=Paint()..color=C.warning.withOpacity(.7)..strokeWidth=3..style=PaintingStyle.stroke..strokeCap=StrokeCap.round;
    final avoid=Paint()..color=C.accent.withOpacity(.5)..strokeWidth=2.5..style=PaintingStyle.stroke..strokeCap=StrokeCap.round;
    final p1=Path()..moveTo(36,44)..quadraticBezierTo(s.width*.35,s.height*.25,s.width*.55,s.height*.48);
    final p2=Path()..moveTo(s.width*.55,s.height*.48)..quadraticBezierTo(s.width*.72,s.height*.62,s.width*.83,s.height*.7);
    final p3=Path()..moveTo(36,110)..quadraticBezierTo(s.width*.28,s.height*.72,s.width*.83,s.height*.7);
    c.drawPath(p1,safe);c.drawPath(p2,caution);c.drawPath(p3,avoid);
  }
  @override bool shouldRepaint(_)=>false;
}