import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});
  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:C.bg,
    body:SafeArea(child:Padding(padding:const EdgeInsets.symmetric(horizontal:20,vertical:16),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Live location',style:TextStyle(color:C.textPrimary,fontSize:22,fontWeight:FontWeight.w800)),
        const SizedBox(height:16),
        SlideUpFade(delay:const Duration(milliseconds:60),child:Container(height:210,
          decoration:BoxDecoration(color:const Color(0xFF081413),borderRadius:BorderRadius.circular(16),
            border:Border.all(color:C.accent.withOpacity(.4),width:1.5)),
          child:ClipRRect(borderRadius:BorderRadius.circular(14),child:Stack(children:[
            CustomPaint(painter:GridPainter(),size:const Size(double.infinity,210)),
            Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
              PulseRing(size:26,color:C.accent,rings:2,child:Container(width:22,height:22,decoration:BoxDecoration(shape:BoxShape.circle,color:C.accent))),
              const SizedBox(height:4),
              Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
                decoration:BoxDecoration(color:C.accent,borderRadius:BorderRadius.circular(5)),
                child:Text('You are here',style:TextStyle(color:C.textPrimary,fontSize:10,fontWeight:FontWeight.w700))),
            ])),
          ])))),
        const SizedBox(height:10),
        SlideUpFade(delay:const Duration(milliseconds:110),child:DCard(borderColor:C.accent,padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
          child:Row(children:[
            Text('LIVE',style:TextStyle(color:C.accent,fontSize:11,fontWeight:FontWeight.w700)),
            const SizedBox(width:10),const WaveBars(),const SizedBox(width:10),
            Text('Broadcasting GPS every 3s',style:TextStyle(color:C.textMuted,fontSize:11)),
          ]))),
        const SizedBox(height:14),
        SlideUpFade(delay:const Duration(milliseconds:160),child:GridView.count(
          crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
          crossAxisSpacing:8,mainAxisSpacing:8,childAspectRatio:1.9,
          children:[
            _Stat(bc:C.accent,   label:'Location',    value:'Saddar, KHI',  vs:12),
            _Stat(bc:C.accent, label:'Sharing',     value:'4 contacts'),
            _Stat(bc:C.warning,  label:'Nearest',     value:'1122 · 0.8km', vs:13),
            _Stat(bc:C.success,  label:'Accuracy',    value:'± 4 metres',   vs:13),
          ])),
        const SizedBox(height:12),
        SlideUpFade(delay:const Duration(milliseconds:200),child:DCard(borderColor:C.accent,padding:const EdgeInsets.symmetric(vertical:12,horizontal:14),
          child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
            Icon(Icons.location_on_rounded,color:C.accent,size:16),const SizedBox(width:6),
            Text('Saddar, Karachi  ·  Tracking since 9 min',style:TextStyle(color:C.textMuted,fontSize:12,fontWeight:FontWeight.w500)),
          ]))),
      ]))));
}
class _Stat extends StatelessWidget {
  final Color bc;final String label,value;final double vs;
  const _Stat({required this.bc,required this.label,required this.value,this.vs=16});
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.all(12),
    decoration:BoxDecoration(color:C.bg2,borderRadius:BorderRadius.circular(12),border:Border.all(color:bc.withOpacity(.5))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
      Container(height:3,width:24,decoration:BoxDecoration(color:bc,borderRadius:BorderRadius.circular(2))),
      const SizedBox(height:6),
      Text(label,style:TextStyle(color:C.textMuted,fontSize:10)),
      const SizedBox(height:3),
      Text(value,style:TextStyle(color:C.textPrimary,fontSize:vs,fontWeight:FontWeight.w700)),
    ]));
}