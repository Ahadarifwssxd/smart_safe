import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

class AddContactPage extends StatefulWidget {
  const AddContactPage({super.key});
  @override State<AddContactPage> createState()=>_AddContactPageState();
}
class _AddContactPageState extends State<AddContactPage>{
  final _name=TextEditingController(),_phone=TextEditingController();
  String _rel='Family'; bool _sms=true,_push=true;
  @override void dispose(){_name.dispose();_phone.dispose();super.dispose();}
  void _save(){
    if(_name.text.isEmpty||_phone.text.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor:C.accent,behavior:SnackBarBehavior.floating,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),
        content:Text('Please fill all fields',style:TextStyle(color:C.textPrimary))));return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor:C.success,behavior:SnackBarBehavior.floating,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),
      content:Text('${_name.text} added to your circle!',style:TextStyle(color:C.textPrimary))));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:C.bg,
    appBar:AppBar(title:const Text('Add Contact'),
      leading:IconButton(icon:const Icon(Icons.arrow_back_ios_rounded,size:18),onPressed:()=>Navigator.pop(context))),
    body:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:20,vertical:8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Center(child:SlideUpFade(child:Column(children:[
        CircleAvatar(radius:35,backgroundColor:C.accent,
          child:Text(_name.text.isEmpty?'?':_name.text[0].toUpperCase(),style:TextStyle(color:C.textPrimary,fontSize:26,fontWeight:FontWeight.w800))),
        const SizedBox(height:8),
        Text('Your new trusted contact',style:TextStyle(color:C.textMuted,fontSize:12)),
      ]))),
      const SizedBox(height:24),
      const SecHeader('Contact info'),
      TextField(controller:_name,onChanged:(_)=>setState((){}),
        decoration:const InputDecoration(labelText:'Full name',prefixIcon:Icon(Icons.person_rounded)),
        style:TextStyle(color:C.textPrimary)),
      const SizedBox(height:12),
      TextField(controller:_phone,keyboardType:TextInputType.phone,
        decoration:const InputDecoration(labelText:'Phone number',hintText:'03XX-XXXXXXX',prefixIcon:Icon(Icons.phone_rounded)),
        style:TextStyle(color:C.textPrimary)),
      const SizedBox(height:20),
      const SecHeader('Relation'),
      Wrap(spacing:8,children:['Family','Friend','Work','Other'].map((r){final s=r==_rel;
        return GestureDetector(onTap:()=>setState(()=>_rel=r),
          child:AnimatedContainer(duration:const Duration(milliseconds:200),
            margin:const EdgeInsets.only(bottom:8),
            padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
            decoration:BoxDecoration(color:s?C.accent:C.bg2,borderRadius:BorderRadius.circular(20),border:Border.all(color:s?C.accent:C.textDim)),
            child:Text(r,style:TextStyle(color:s?C.textPrimary:C.textMuted,fontSize:13,fontWeight:s?FontWeight.w700:FontWeight.normal))));
      }).toList()),
      const SizedBox(height:20),
      const SecHeader('Notify via'),
      DCard(child:Column(children:[
        TRow(label:'SMS Alert',sub:'Send SMS even without internet',value:_sms,onChanged:(v)=>setState(()=>_sms=v)),
        Divider(color:C.border,height:1),
        TRow(label:'App Push Notification',sub:'Alert via SmartSafe app',value:_push,onChanged:(v)=>setState(()=>_push=v)),
      ])),
      const SizedBox(height:16),
      DCard(borderColor:C.warning,child:Row(children:[
        Icon(Icons.info_outline_rounded,color:C.warning,size:18),const SizedBox(width:10),
        Expanded(child:Text('This contact will be alerted on every SOS and crash event.',style:TextStyle(color:C.textMuted,fontSize:11))),
      ])),
      const SizedBox(height:20),
      BigBtn(label:'Save Contact',color:C.accent,icon:Icons.person_add_rounded,onTap:_save),
      const SizedBox(height:20),
    ]))));
}