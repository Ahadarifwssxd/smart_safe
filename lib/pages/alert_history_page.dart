import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../models/models.dart';

class AlertHistoryPage extends StatefulWidget {
  const AlertHistoryPage({super.key});
  @override State<AlertHistoryPage> createState()=>_AlertHistoryPageState();
}
class _AlertHistoryPageState extends State<AlertHistoryPage>{
  AlertType? _filter;
  List<AlertEvent> get _list=>_filter==null?demoHistory:demoHistory.where((e)=>e.type==_filter).toList();
  String _ago(DateTime t){final d=DateTime.now().difference(t);if(d.inMinutes<60)return '${d.inMinutes}m ago';if(d.inHours<24)return '${d.inHours}h ago';return '${d.inDays}d ago';}

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:C.bg,
    body:SafeArea(child:Padding(padding:const EdgeInsets.symmetric(horizontal:20,vertical:16),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Row(children:[
            GestureDetector(onTap:()=>Navigator.pop(context),child:Icon(Icons.arrow_back_ios_new_rounded,color:C.textPrimary,size:20)),
            const SizedBox(width:12),
            Text('Alert History',style:TextStyle(color:C.textPrimary,fontSize:22,fontWeight:FontWeight.w800)),
          ]),
          Text('Clear all',style:TextStyle(color:C.textMuted,fontSize:12)),
        ]),
        const SizedBox(height:16),
        SizedBox(height:34,child:ListView(scrollDirection:Axis.horizontal,children:[
          _Chip(label:'All',  active:_filter==null,           color:C.accent,   onTap:()=>setState(()=>_filter=null)),const SizedBox(width:8),
          _Chip(label:'SOS',  active:_filter==AlertType.sos,  color:C.accent,    onTap:()=>setState(()=>_filter=AlertType.sos)),const SizedBox(width:8),
          _Chip(label:'Crash',active:_filter==AlertType.crash,color:C.warning,  onTap:()=>setState(()=>_filter=AlertType.crash)),const SizedBox(width:8),
          _Chip(label:'Safe', active:_filter==AlertType.safe, color:C.success,  onTap:()=>setState(()=>_filter=AlertType.safe)),const SizedBox(width:8),
          _Chip(label:'GPS',  active:_filter==AlertType.gps,  color:C.accent,   onTap:()=>setState(()=>_filter=AlertType.gps)),
        ])),
        const SizedBox(height:14),
        Row(children:[
          _Mini('Total','${demoHistory.length}',C.accent),const SizedBox(width:8),
          _Mini('SOS','${demoHistory.where((e)=>e.type==AlertType.sos).length}',C.accent),const SizedBox(width:8),
          _Mini('Crash','${demoHistory.where((e)=>e.type==AlertType.crash).length}',C.warning),const SizedBox(width:8),
          _Mini('Safe','${demoHistory.where((e)=>e.type==AlertType.safe).length}',C.success),
        ]),
        const SizedBox(height:14),
        Expanded(child:_list.isEmpty
          ?Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.history_rounded,color:C.textMuted,size:48),const SizedBox(height:12),Text('No events',style:TextStyle(color:C.textMuted,fontSize:14))]))
          :ListView.separated(itemCount:_list.length,separatorBuilder:(_,__)=>const SizedBox(height:8),
            itemBuilder:(_,i){final e=_list[i];return SlideUpFade(delay:Duration(milliseconds:i*40),child:DCard(padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
              child:Row(children:[
                Container(width:36,height:36,decoration:BoxDecoration(color:e.color.withOpacity(.15),borderRadius:BorderRadius.circular(10)),child:Icon(e.icon,color:e.color,size:18)),
                const SizedBox(width:12),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(e.title,style:TextStyle(color:C.textPrimary,fontSize:13,fontWeight:FontWeight.w600)),
                  if(e.location.isNotEmpty)Text(e.location,style:TextStyle(color:C.textMuted,fontSize:11)),
                  Text(_ago(e.time),style:TextStyle(color:C.textMuted,fontSize:10)),
                ])),
                StatusChip(label:e.label,color:e.color),
              ])));})),
      ]))));
}
class _Chip extends StatelessWidget {
  final String label;final bool active;final Color color;final VoidCallback onTap;
  const _Chip({required this.label,required this.active,required this.color,required this.onTap});
  @override Widget build(BuildContext context)=>GestureDetector(onTap:onTap,
    child:AnimatedContainer(duration:const Duration(milliseconds:200),
      padding:const EdgeInsets.symmetric(horizontal:14),
      decoration:BoxDecoration(color:active?color:C.bg2,borderRadius:BorderRadius.circular(20),border:Border.all(color:active?color:C.textDim)),
      child:Center(child:Text(label,style:TextStyle(color:active?C.textPrimary:C.textMuted,fontSize:12,fontWeight:active?FontWeight.w700:FontWeight.normal)))));
}
class _Mini extends StatelessWidget {
  final String label,value;final Color color;
  const _Mini(this.label,this.value,this.color);
  @override Widget build(BuildContext context)=>Expanded(child:Container(
    padding:const EdgeInsets.symmetric(vertical:10),
    decoration:BoxDecoration(color:C.bg2,borderRadius:BorderRadius.circular(10),border:Border.all(color:color.withOpacity(.3))),
    child:Column(children:[Text(value,style:TextStyle(color:color,fontSize:18,fontWeight:FontWeight.w800)),Text(label,style:TextStyle(color:C.textMuted,fontSize:10))])));
}