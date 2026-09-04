import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import '../models/models.dart';

class ContactsPage extends StatelessWidget {
  final VoidCallback onAddContact;
  const ContactsPage({super.key, required this.onAddContact});

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:C.bg,
    body:SafeArea(child:Padding(padding:const EdgeInsets.symmetric(horizontal:20,vertical:16),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Text('My circle',style:TextStyle(color:C.textPrimary,fontSize:22,fontWeight:FontWeight.w800)),
          GestureDetector(onTap:onAddContact,child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
            decoration:BoxDecoration(color:C.accent,borderRadius:BorderRadius.circular(20)),
            child:Row(children:[Icon(Icons.add,color:C.textPrimary,size:14),const SizedBox(width:4),Text('Add',style:TextStyle(color:C.textPrimary,fontSize:12,fontWeight:FontWeight.w600))]))),
        ]),
        const SizedBox(height:16),
        Expanded(child:ListView(children:[
          ...demoContacts.asMap().entries.map((e)=>SlideUpFade(delay:Duration(milliseconds:60*e.key),
            child:Padding(padding:const EdgeInsets.only(bottom:10),child:_CCard(contact:e.value)))),
          const SizedBox(height:10),
          DCard(borderColor:C.accent,child:Row(children:[
            Container(width:36,height:36,decoration:BoxDecoration(color:C.accent.withOpacity(.15),borderRadius:BorderRadius.circular(8)),
              child:const Center(child:Text('📱',style:TextStyle(fontSize:18)))),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Shake to alert',style:TextStyle(color:C.textPrimary,fontSize:13,fontWeight:FontWeight.w600)),
              Text('All 4 contacts notified at once',style:TextStyle(color:C.textMuted,fontSize:11)),
            ])),
          ])),
          const SizedBox(height:8),
          DCard(borderColor:C.warning,child:Row(children:[
            Container(width:36,height:36,decoration:BoxDecoration(color:C.warning.withOpacity(.15),borderRadius:BorderRadius.circular(8)),
              child:const Center(child:Text('💬',style:TextStyle(fontSize:18)))),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('SMS backup enabled',style:TextStyle(color:C.textPrimary,fontSize:13,fontWeight:FontWeight.w600)),
              Text('Works without internet connection',style:TextStyle(color:C.textMuted,fontSize:11)),
            ])),
          ])),
        ])),
      ]))));
}

class _CCard extends StatefulWidget {
  final Contact contact;const _CCard({required this.contact});
  @override State<_CCard> createState()=>_CCardState();
}
class _CCardState extends State<_CCard>{
  bool _p=false;
  @override Widget build(BuildContext context){
    final c=widget.contact;
    return GestureDetector(onTapDown:(_)=>setState(()=>_p=true),onTapUp:(_)=>setState(()=>_p=false),onTapCancel:()=>setState(()=>_p=false),
      child:AnimatedContainer(duration:const Duration(milliseconds:150),
        padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
        decoration:BoxDecoration(color:_p?C.bg3:C.bg2,borderRadius:BorderRadius.circular(12),
          border:Border.all(color:_p?C.accent.withOpacity(.4):C.textPrimary.withOpacity(.06))),
        child:Row(children:[
          CircleAvatar(radius:22,backgroundColor:c.color,child:Text(c.initial,style:TextStyle(color:C.textPrimary,fontSize:16,fontWeight:FontWeight.w700))),
          const SizedBox(width:14),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(c.name,style:TextStyle(color:C.textPrimary,fontSize:14,fontWeight:FontWeight.w700)),
            Text(c.role,style:TextStyle(color:C.textMuted,fontSize:11)),
            Text(c.phone,style:TextStyle(color:C.textMuted,fontSize:10)),
          ])),
          Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
            Row(children:[BlinkDot(color:c.isOnline?C.accent:C.warning),const SizedBox(width:5),
              Text(c.isOnline?'Online':'Away',style:TextStyle(color:c.isOnline?C.accent:C.warning,fontSize:11,fontWeight:FontWeight.w500))]),
            const SizedBox(height:6),
            Row(children:[
              StatusChip(label:'SMS',color:c.smsAlert?C.accent:C.textMuted),
              const SizedBox(width:4),
              StatusChip(label:'Push',color:c.pushAlert?C.accent:C.textMuted),
            ]),
          ]),
        ])));
  }
}