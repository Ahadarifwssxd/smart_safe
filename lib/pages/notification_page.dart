import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../models/models.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override State<NotificationsPage> createState()=>_NotificationsPageState();
}
class _NotificationsPageState extends State<NotificationsPage>{
  List<AppNotif> _notifs=List.from(demoNotifs);
  int get _unread=>_notifs.where((n)=>!n.isRead).length;
  String _ago(DateTime t){final d=DateTime.now().difference(t);if(d.inMinutes<60)return '${d.inMinutes}m ago';if(d.inHours<24)return '${d.inHours}h ago';return '${d.inDays}d ago';}
  void _markAll()=>setState(()=>_notifs=_notifs.map((n)=>AppNotif(title:n.title,body:n.body,time:n.time,type:n.type,isRead:true)).toList());
  void _read(AppNotif n)=>setState(()=>_notifs=_notifs.map((nn)=>nn.title==n.title?AppNotif(title:nn.title,body:nn.body,time:nn.time,type:nn.type,isRead:true):nn).toList());

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:C.bg,
    body:SafeArea(child:Padding(padding:const EdgeInsets.symmetric(horizontal:20,vertical:16),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Row(children:[
            GestureDetector(onTap:()=>Navigator.pop(context),child:Icon(Icons.arrow_back_ios_new_rounded,color:C.textPrimary,size:20)),
            const SizedBox(width:12),
            Text('Notifications',style:TextStyle(color:C.textPrimary,fontSize:22,fontWeight:FontWeight.w800)),
            if(_unread>0)...[const SizedBox(width:10),Container(width:22,height:22,decoration:BoxDecoration(shape:BoxShape.circle,color:C.accent),
              child:Center(child:Text('$_unread',style:TextStyle(color:C.textPrimary,fontSize:11,fontWeight:FontWeight.w700))))],
          ]),
          if(_unread>0)GestureDetector(onTap:_markAll,child:Text('Mark all read',style:TextStyle(color:C.accent,fontSize:12,fontWeight:FontWeight.w500))),
        ]),
        const SizedBox(height:16),
        if(_unread>0)...[
          const SecHeader('New'),
          ..._notifs.where((n)=>!n.isRead).map((n)=>Padding(padding:const EdgeInsets.only(bottom:8),child:_NCard(notif:n,ago:_ago(n.time),onTap:()=>_read(n)))),
          const SizedBox(height:8),
        ],
        if(_notifs.any((n)=>n.isRead))...[
          const SecHeader('Earlier'),
          Expanded(child:ListView(children:[..._notifs.where((n)=>n.isRead).toList().asMap().entries.map((e)=>SlideUpFade(delay:Duration(milliseconds:e.key*40),
            child:Padding(padding:const EdgeInsets.only(bottom:8),child:_NCard(notif:e.value,ago:_ago(e.value.time)))))])),
        ],
      ]))));
}
class _NCard extends StatelessWidget {
  final AppNotif notif;final String ago;final VoidCallback? onTap;
  const _NCard({required this.notif,required this.ago,this.onTap});
  @override Widget build(BuildContext context)=>GestureDetector(onTap:onTap,
    child:AnimatedContainer(duration:const Duration(milliseconds:200),
      padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(color:notif.isRead?C.bg2:C.bg3,borderRadius:BorderRadius.circular(12),
        border:Border.all(color:notif.isRead?C.textPrimary.withOpacity(.06):notif.color.withOpacity(.3))),
      child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Container(width:38,height:38,decoration:BoxDecoration(color:notif.color.withOpacity(.15),borderRadius:BorderRadius.circular(10)),child:Icon(notif.icon,color:notif.color,size:18)),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(notif.title,style:TextStyle(color:C.textPrimary,fontSize:13,fontWeight:notif.isRead?FontWeight.w500:FontWeight.w700)),
          const SizedBox(height:2),
          Text(notif.body,style:TextStyle(color:C.textMuted,fontSize:11)),
          const SizedBox(height:4),
          Text(ago,style:TextStyle(color:C.textDim,fontSize:10)),
        ])),
        if(!notif.isRead)Container(width:8,height:8,decoration:BoxDecoration(shape:BoxShape.circle,color:notif.color)),
      ])));
}