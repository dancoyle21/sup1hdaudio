#define CONNECTS_NUM	16

class MyMass:CMass
{
  F64 radius;
  U8 nid,type,num_connects,cur_connect;
  U32 audio_widget_capabilities;
  U8 connect_lst[CONNECTS_NUM];
  U8 gain_lst[CONNECTS_NUM];
  U32 pin_capabilities,pin_sense,
	pcm_size_rates,
	in_amp_cap,out_amp_cap;
  U8 pin_widget_ctl;
  Bool disabled;
};

class MySpring:CSpring
{
  I64 color;
};

CMathODE *ode=NULL;

#define BORDER	10

U0 DrawIt(CTask *task,CDC *dc)
{
  Bool old_suspend;
  I16 *buf;
  I64 i,cxx,cyy,
	cy=task->pix_height>>1;
  F64 dx,dy,d;
  MyMass   *tmpm;
  MySpring *tmps;

  old_suspend=Suspend(task);
  tmps=ode->next_spring;
  while (tmps!=&ode->next_spring) {
    dc->color=tmps->color;
    GrLine(dc,tmps->end1->x,tmps->end1->y,
	  tmps->end2->x,tmps->end2->y);
    cxx=(tmps->end1->x+tmps->end2->x)/2;
    cyy=(tmps->end1->y+tmps->end2->y)/2;
    dx=tmps->end1->x-tmps->end2->x;
    dy=tmps->end1->y-tmps->end2->y;
    d=Sqrt(dx*dx+dy*dy);
    dx/=d;
    dy/=d;
    GrLine(dc,cxx,cyy,cxx+3.0*dy-3.0*dx,cyy-3.0*dx-3.0*dy);
    GrLine(dc,cxx,cyy,cxx-3.0*dy-3.0*dx,cyy+3.0*dx-3.0*dy);
    tmps=tmps->next;
  }

  tmpm=ode->next_mass;
  while (tmpm!=&ode->next_mass) {
    if (tmpm->disabled)
      dc->color=BLUE;
    else
      dc->color=LTBLUE;
    GrCircle(dc,tmpm->x,tmpm->y,tmpm->radius);
    GrPrint(dc,tmpm->x,tmpm->y-FONT_HEIGHT/2,"%02X%3tZ",
	  tmpm->nid,tmpm->type,
	  "ST_AUDIO_WIDGET_TYPES");
    tmpm=tmpm->next;
  }
  Suspend(task,old_suspend);
  dc->color=BLUE;
  buf=hda.istr0_buf[0];
  for (i=0;i<SND_BUF_LEN;i++)
    GrPlot(dc,i*task->pix_width/SND_BUF_LEN,
	  cy-buf[i]*cy/I16_MAX);
}

U0 MyDerivative(CMathODE *ode,F64,COrder2D3 *,COrder2D3 *)
{
//The forces due to springs and drag are
  //automatically handled by the
  //ode code.We can add new forces
  //here.
  CTask *task=ode->win_task;
  I64 h=task->pix_width,v=task->pix_height;
  F64 d,dd;
  CD3 p;
  MyMass *tmpm1,*tmpm2;

  tmpm1=ode->next_mass;
  while (tmpm1!=&ode->next_mass) {
    tmpm2=tmpm1->next;
    while (tmpm2!=&ode->next_mass) {
      D3Sub(&p,&tmpm2->state->x,&tmpm1->state->x);
      dd=D3NormSqr(&p);
      if (dd<=Sqr(tmpm1->radius+tmpm2->radius)) {
	d=Sqrt(dd)+0.0001;
	dd=10.0*Sqr(Sqr(Sqr(tmpm1->radius+tmpm2->radius)-dd));
	D3MulEqu(&p,dd/d);
	D3AddEqu(&tmpm2->DstateDt->DxDt,&p);
	D3SubEqu(&tmpm1->DstateDt->DxDt,&p);
      } else {
	D3MulEqu(&p,100000.0/dd);
	D3AddEqu(&tmpm2->DstateDt->DxDt,&p);
	D3SubEqu(&tmpm1->DstateDt->DxDt,&p);
      }
      tmpm2=tmpm2->next;
    }
    if (tmpm1->state->x<BORDER)
      tmpm1->DstateDt->DxDt+=1000*Sqr(tmpm1->state->x-BORDER);
    if (tmpm1->state->y<BORDER)
      tmpm1->DstateDt->DyDt+=1000*Sqr(tmpm1->state->y-BORDER);
    if (tmpm1->state->x>h-BORDER-FONT_WIDTH*6)
      tmpm1->DstateDt->DxDt-=1000*
	    Sqr(tmpm1->state->x-(h-BORDER-FONT_WIDTH*6));
    if (tmpm1->state->y>v-BORDER)
      tmpm1->DstateDt->DyDt-=1000*Sqr(tmpm1->state->y-(v-BORDER));
    tmpm1=tmpm1->next;
  }
}

MyMass *PlaceMass(I64 nid)
{
  MyMass *tmpm=CAlloc(sizeof(MyMass));
  tmpm->mass=1.0;
  tmpm->drag_profile_factor=100.0;
  tmpm->radius=5;
  tmpm->nid=nid;
  tmpm->gain_lst[0]=0x7F;
  MemSet(tmpm->gain_lst+1,0x80,(CONNECTS_NUM-1)*sizeof(U8));
  QueIns(tmpm,ode->last_mass);
  return tmpm;
}

MyMass *FindMassByNID(I64 nid)
{
  MyMass   *tmpm;
  tmpm=ode->next_mass;
  while (tmpm!=&ode->next_mass) {
    if (tmpm->nid==nid)
      return tmpm;
    tmpm=tmpm->next;
  }
  return NULL;
}

MyMass *FindMassByXY(I64 x,I64 y)
{
  I64 dd,best_dd=I64_MAX;
  MyMass *tmpm,*res=NULL;
  tmpm=ode->next_mass;
  while (tmpm!=&ode->next_mass) {
    dd=SqrI64(tmpm->x-x)+SqrI64(tmpm->y-y);
    if (dd<best_dd) {
      res=tmpm;
      best_dd=dd;
    }
    tmpm=tmpm->next;
  }
  return res;
}

I64 FindConnectIndex(MyMass *tmpm,I64 nid)
{
  I64 i;
  for (i=0;i<tmpm->num_connects;i++)
    if (tmpm->connect_lst[i]==nid)
      return i;
  return -1;
}

MySpring *PlaceSpring(MyMass *tmpm1,MyMass *tmpm2)
{
  MySpring *tmps=CAlloc(sizeof(MySpring));
  tmps->end1=tmpm1;
  tmps->end2=tmpm2;
  tmps->const=10;
  tmps->rest_len=0;
  tmps->color=LTGRAY;
  QueIns(tmps,ode->last_spring);
  return tmps;
}

U0 RedoSprings()
{
  I64 i,k;
  MyMass   *tmpm,*tmpm1;
  MySpring *tmps;

  QueDel(&ode->next_spring,TRUE);
  tmpm=ode->next_mass;
  while (tmpm!=&ode->next_mass) {
    for (i=0;i<tmpm->num_connects;i++) {
      if ((k=tmpm->connect_lst[i]) &&
	    (tmpm1=FindMassByNID(k)) ) {
	tmps=PlaceSpring(tmpm,tmpm1);
	switch (tmpm->type) {
	  case AWT_MIXER:
	    if (!(tmpm->gain_lst[i]&0x80)) { //If not mute
	      tmps->color=GREEN;
	      tmps->const=100;
	    }
	    break;
	  case AWT_INPUT:
	  case AWT_SELECTOR:
	  case AWT_PIN_COMPLEX:
	  case AWT_VENDOR:
	    if (i==tmpm->cur_connect) {
	      tmps->color=RED;
	      tmps->const=100;
	    }
	    break;
	}
      }
    }
    tmpm=tmpm->next;
  }
}

U0 Init()
{
  ode=ODENew(0,1e-4,ODEF_HAS_MASSES);
  ode->derive=&MyDerivative;
  ode->drag_v2=0.002;
  ode->drag_v3=0.00001;
  ode->acceleration_limit=5e3;

  QueIns(ode,Fs->last_ode);
}

U0 CleanUp()
{
  QueRem(ode);
  QueDel(&ode->next_mass,TRUE);
  QueDel(&ode->next_spring,TRUE);
  ODEDel(ode);
}

U0 HDCfgConnectLst(MyMass *tmpm,I64 cad,I64 nid)
{
  I64 i,j,connection_lst_len;
  j=HDWriteCORBSync(cad,nid,VERB_GET_PARAM+P_CONNECT_LST_LEN);
  connection_lst_len=j&127;
  if (j&128) { //Long form?
    for (i=0;i<connection_lst_len;i+=2) {
      j=HDWriteCORBSync(cad,nid,VERB_GET_CONNECT_LST+i);
      tmpm->connect_lst[tmpm->num_connects++]=j.u16[0];
      if (i+1<connection_lst_len)
	tmpm->connect_lst[tmpm->num_connects++]=j.u16[1];
    }
  } else {
    for (i=0;i<connection_lst_len;i+=4) {
      j=HDWriteCORBSync(cad,nid,VERB_GET_CONNECT_LST+i);
      tmpm->connect_lst[tmpm->num_connects++]=j.u8[0];
      if (i+1<connection_lst_len)
	tmpm->connect_lst[tmpm->num_connects++]=j.u8[1];
      if (i+2<connection_lst_len)
	tmpm->connect_lst[tmpm->num_connects++]=j.u8[2];
      if (i+3<connection_lst_len)
	tmpm->connect_lst[tmpm->num_connects++]=j.u8[3];
    }
  }
}

U0 HDCfgTraverse(I64 cad,I64 nid)
{
  I64 i,j;
  MyMass *tmpm=PlaceMass(nid);
  j=HDWriteCORBSync(cad,nid,VERB_GET_PARAM+P_SUBNODE_CNT);
  if (j.u16[0]) {
    tmpm->type=AWT_NODE;
    for (i=j.u16[1];i<j.u16[1]+j.u16[0];i++)
      HDCfgTraverse(cad,i);
  } else {
    tmpm->audio_widget_capabilities=
	  HDWriteCORBSync(cad,nid,VERB_GET_PARAM+P_AUDIO_WIDGET_CAP);
    tmpm->pcm_size_rates=
	  HDWriteCORBSync(cad,nid,VERB_GET_PARAM+P_SAMPLE_SIZE_RATE_CAP);
    tmpm->in_amp_cap=HDWriteCORBSync(cad,nid,VERB_GET_PARAM+P_INPUT_AMP_CAP);
    tmpm->out_amp_cap=HDWriteCORBSync(cad,nid,VERB_GET_PARAM+P_OUTPUT_AMP_CAP);
    tmpm->type=tmpm->audio_widget_capabilities>>20&15;
    switch (tmpm->type) {
      case AWT_PIN_COMPLEX:
	tmpm->pin_widget_ctl=
	      HDWriteCORBSync(cad,nid,VERB_PIN_WIDGET_CTL_GET);
	tmpm->pin_capabilities=
	      HDWriteCORBSync(cad,nid,VERB_GET_PARAM+P_PIN_CAP);
	if (Bt(&tmpm->pin_capabilities,0) ||
	      Bt(&tmpm->pin_capabilities,2))
	  tmpm->pin_sense=HDWriteCORBSync(cad,nid,VERB_PIN_SENSE_GET);
	HDWriteCORBSync(cad,nid,VERB_CONNECT_SEL_SET+0x00);
	break;
      case AWT_INPUT:
	tmpm->disabled=TRUE;
      case AWT_SELECTOR:
      case AWT_VENDOR:
	HDWriteCORBSync(cad,nid,VERB_CONNECT_SEL_SET+0x00);
	break;
    }
    if (Bt(&tmpm->audio_widget_capabilities,8))
      HDCfgConnectLst(tmpm,cad,nid);
  }
}

U0 HDCfgRandomizeXY()
{
  I64 h=Fs->pix_width,v=Fs->pix_height;
  MyMass   *tmpm;
  tmpm=ode->next_mass;
  while (tmpm!=&ode->next_mass) {
    tmpm->x=RandU32%(h-2*BORDER-FONT_WIDTH*6)+BORDER;
    tmpm->y=RandU32%(v-2*BORDER)+BORDER;
    tmpm=tmpm->next;
  }
}

U0 HDCfgPopUpInfoTask(MyMass *tmpm)
{
  I64 i;
  "$$FG,RED$$NID:$$FG$$0x%02X$$FG,RED$$Type:$$FG$$%Z\n",
	tmpm->nid,tmpm->type,"ST_AUDIO_WIDGET_TYPES";

  i=tmpm->audio_widget_capabilities;
  "\n$$FG,RED$$Audio Widget Capabilities:$$FG$$\n";
  if (Bt(&i,0))
    "Stereo,";
  if (Bt(&i,1))
    "In Amp,";
  if (Bt(&i,2))
    "Out Amp,";
  if (Bt(&i,3))
    "AmpOverride,";
  if (Bt(&i,4))
    "FmtOverride,";
  if (Bt(&i,5))
    "Stripe,";
  if (Bt(&i,6))
    "Proc Wgt,";
  if (Bt(&i,7))
    "Unsolicited,";
  if (Bt(&i,8))
    "Cnt Lst,";
  if (Bt(&i,9))
    "Digital,";
  if (Bt(&i,10))
    "Power Ctrl,";
  if (Bt(&i,11))
    "Left/Right Swap,";
  "Delay:%d\n",i.u16[1]&0xF;

  i=tmpm->in_amp_cap;
  "\n$$FG,RED$$Input Amp Capabilities:$$FG$$\n"
	"Offset:0x%02X Steps:0x%02X StepSize:%5.2fdB Mutable:%d\n",
	i&127,i.u8[1]&127+1,0.25*(i.u16[1]&127),Bt(&i,31);

  i=tmpm->out_amp_cap;
  "\n$$FG,RED$$Output Amp Capabilities:$$FG$$\n"
	"Offset:0x%02X Steps:0x%02X StepSize:%5.2fdB Mutable:%d\n",
	i&127,i.u8[1]&127+1,0.25*(i.u16[1]&127),Bt(&i,31);

  "\n$$FG,RED$$Size Rates Capabilities:$$FG$$\n";
  for (i=0;i<21;i++)
    if (Bt(&tmpm->pcm_size_rates,i))
      "%z",i,
	    " 8.0kHz\0 11.025kHz\0 16.0kHz\0 22.05kHz\0"
	    " 32.0kHz\0 44.1kHz\0 48.0kHz\0 88.2kHz\0"
	    " 96.0kHz\0 176.4kHz\0 192.0kHz\0 384kHz\0"
	    "\0\0\0\0"
	    " 8Bit\0 16bit\0 20Bit\0 24Bit\0 32Bit\0";
  '\n';

  "\n$$FG,RED$$Connection Lst:$$FG$$\n";
  for (i=0;i<tmpm->num_connects;i++)
    "%02X,",tmpm->connect_lst[i];
  '\n';

  "\n$$FG,RED$$Gain Lst:$$FG$$\n";
  for (i=0;i<tmpm->num_connects;i++)
    "%02X,",tmpm->gain_lst[i];
  '\n';

  switch (tmpm->type) {
    case AWT_PIN_COMPLEX:
      "\n$$FG,RED$$Pin Capabilities:$$FG$$\n";
      i=tmpm->pin_capabilities;
      if (Bt(&i,0))
	"Impedance Sense,";
      if (Bt(&i,1))
	"Trigger Required,";
      if (Bt(&i,2))
	"Presence Detect,";
      if (Bt(&i,3))
	"Headphone Drive,";
      if (Bt(&i,4))
	"Output,";
      if (Bt(&i,5))
	"Input,";
      if (Bt(&i,6))
	"Balanced,";
      if (Bt(&i,16))
	"EAPD,";
      "Vref:%02X\n\n",i.u8[1];
      if (Bt(&tmpm->pin_capabilities,0) ||
	    Bt(&tmpm->pin_capabilities,2))
	tmpm->pin_sense=HDWriteCORBSync(hda.cad,
	      tmpm->nid,VERB_PIN_SENSE_GET);
      if (Bt(&tmpm->pin_capabilities,0))
	"Impedance Measurement:%08X\n",tmpm->pin_sense&0x7FFFFFFF;
      if (Bt(&tmpm->pin_capabilities,2))
	"Presence:%d\n",Bt(&tmpm->pin_sense,31);
      "\n\nPin widget ctrl bits:\n"
	    "7: High phn enable (low impedance output amp)\n"
	    "6: Output Enable\n"
	    "5: Input Enable\n"
	    "0-2: Vref 0=HiZ 1=50% 2=Gnd 4=80% 5=100%\n";
      tmpm->pin_widget_ctl=GetI64("Widget Ctrl (0x%02X):",
	    tmpm->pin_widget_ctl,0,0xFF);
      HDWriteCORBSync(hda.cad,tmpm->nid,
	    VERB_PIN_WIDGET_CTL_SET+tmpm->pin_widget_ctl);
      break;
    case AWT_INPUT:
      "Disable";
      if (tmpm->disabled=YorN)
	HDWriteCORBSync(hda.cad,tmpm->nid,VERB_CHAN_STREAM_ID_SET+0x00);
      else
	HDWriteCORBSync(hda.cad,tmpm->nid,VERB_CHAN_STREAM_ID_SET+0x20);
      '\n';
      break;
    case AWT_OUTPUT:
      "Disable";
      if (tmpm->disabled=YorN)
	HDWriteCORBSync(hda.cad,tmpm->nid,VERB_CHAN_STREAM_ID_SET+0x00);
      else
	HDWriteCORBSync(hda.cad,tmpm->nid,VERB_CHAN_STREAM_ID_SET+0x10);
      '\n';
      break;
  }
}

U0 HDCfgPopUpInfo(MyMass *tmpm)
{
  U8 buf[STR_LEN];
  StrPrint(buf,
	"HDCfgPopUpInfoTask(0x%X);\"\\n\\nPress SHIFT-ESC\\n\\n\\n\\n\";View;",
	tmpm);
  Fs->win_inhibit|=WIF_SELF_ODE;
  Fs->draw_it=NULL;
  Refresh;
  PopUp(buf,Fs);
  Fs->win_inhibit&=~WIF_SELF_ODE;
  Fs->draw_it=&DrawIt;
}

U0 HDCfgEdLink(MyMass *tmpm_out,MyMass *tmpm_in)
{
  I64 i,j;
  if ((i=FindConnectIndex(tmpm_in,tmpm_out->nid))>=0) {
    switch (tmpm_in->type) {
      case AWT_MIXER:
	MemSet(tmpm_in->gain_lst,0x80,sizeof(U8)*CONNECTS_NUM);
	tmpm_in->gain_lst[i]=0x7F;
	for (j=0;j<tmpm_in->num_connects;j++)
	  HDWriteCORBSync(hda.cad,tmpm_in->nid,
		VERB_AMPLIFIER_GAIN_SET+0x7000+tmpm_in->gain_lst[j]+j<<8);
	break;
      case AWT_INPUT:
      case AWT_SELECTOR:
      case AWT_PIN_COMPLEX:
      case AWT_VENDOR:
	tmpm_in->cur_connect=i;
	HDWriteCORBSync(hda.cad,tmpm_in->nid,VERB_CONNECT_SEL_SET+i);
	break;
    }
    RedoSprings;
  }
}

U0 HDCfgSave()
{
  CDoc *doc=DocNew;
  I64 i;
  MyMass   *tmpm;
  DocPrint(doc,"//This file was generated by "
	"$$LK,\"::/TempleOS/Adam/Snd/HDCfg.HC.Z\","
	"\"FI:::/TempleOS/Adam/Snd/HDCfg.HC\"$$\n\n"
	"U0 MyHDCfg()\n{\n");
  tmpm=ode->next_mass;
  while (tmpm!=&ode->next_mass) {
    DocPrint(doc,"  //0x%02X %Z\n",tmpm->nid,tmpm->type,
	  "ST_AUDIO_WIDGET_TYPES");
    if (tmpm->num_connects) {
      DocPrint(doc,"//Connection Lst:");
      for (i=0;i<tmpm->num_connects;i++) {
	if (i==tmpm->cur_connect)
	  DocPrint(doc,"*");
	DocPrint(doc,"0x%02X ",tmpm->connect_lst[i]);
      }
      DocPrint(doc,"\n");
      if (tmpm->type==AWT_MIXER) {
	DocPrint(doc,"//Gain Lst:");
	for (i=0;i<tmpm->num_connects;i++)
	  DocPrint(doc,"0x%02X ",tmpm->gain_lst[i]);
	DocPrint(doc,"\n");
      }
    }
    switch (tmpm->type) {
      case AWT_OUTPUT:
	if (tmpm->disabled)
	  DocPrint(doc,
		"HDWriteCORBSync(hda.cad,0x%02X,"
		"VERB_CHAN_STREAM_ID_SET+0x00);\n",
		tmpm->nid);
	else
	  DocPrint(doc,
		"HDWriteCORBSync(hda.cad,0x%02X,"
		"VERB_CHAN_STREAM_ID_SET+0x10);\n",
		tmpm->nid);
	break;
      case AWT_MIXER:
	DocPrint(doc,
	      "HDWriteCORBSync(hda.cad,0x%02X,"
	      "VERB_AMPLIFIER_GAIN_SET+0xB07F);\n",
	      tmpm->nid);
	for (i=0;i<tmpm->num_connects;i++)
	  DocPrint(doc,
		"HDWriteCORBSync(hda.cad,0x%02X,"
		"VERB_AMPLIFIER_GAIN_SET+0x%04X);\n",
		tmpm->nid,0x7000+tmpm->gain_lst[i]+i<<8);
	break;
      case AWT_INPUT:
	if (tmpm->disabled)
	  DocPrint(doc,
		"HDWriteCORBSync(hda.cad,0x%02X,"
		"VERB_CHAN_STREAM_ID_SET+0x00);\n",
		tmpm->nid);
	else
	  DocPrint(doc,
		"HDWriteCORBSync(hda.cad,0x%02X,"
		"VERB_CHAN_STREAM_ID_SET+0x20);\n",
		tmpm->nid);
	goto here;
      case AWT_PIN_COMPLEX:
	DocPrint(doc,
	      "HDWriteCORBSync(hda.cad,0x%02X,"
	      "VERB_PIN_WIDGET_CTL_SET+0x%02X);\n",
	      tmpm->nid,tmpm->pin_widget_ctl);
      case AWT_SELECTOR:
      case AWT_VENDOR:
here:
	if (tmpm->num_connects>1)
	  DocPrint(doc,
		"HDWriteCORBSync(hda.cad,0x%02X,"
		"VERB_CONNECT_SEL_SET+0x%02X);\n",
		tmpm->nid,tmpm->cur_connect);
	break;
    }
    DocPrint(doc,"\n");
    tmpm=tmpm->next;
  }
  DocPrint(doc,"LBtr(&sys_semas[SEMA_SND],0);\n"
	"}\n\nif (snd_dev==SD_HD_AUDIO)\n"
	"MyHDCfg;\n");
  StrCpy(doc->filename.name,"~/HDAudioCfg.HC.Z");
  DocWrite(doc);
  DocDel(doc);
}

U0 HDCfg()
{
  I64 arg1,arg2;
  MyMass *tmpm1=NULL,*tmpm2=NULL;

  if (snd_dev!=SD_HD_AUDIO) {
    "HD Audio not detected\n";
    return;
  }

  MenuPush(
	"File {"
	"  Abort(,CH_SHIFT_ESC);"
	"  Exit(,CH_ESC);"
	"}"
	"Edit {"
	"  Randomize(,'\n');"
	"  Options(,CH_SPACE);"
	"}"
	);
  SettingsPush; //See $LK,"SettingsPush",A="MN:SettingsPush"$
  DocBottom;
  AutoComplete;
  WinBorder;
  WinMax;
  DocCursor;
  DocClear;
  Fs->win_inhibit=WIF_SELF_MS_L|WIF_SELF_MS_R|WIG_DBL_CLICK|WIF_SELF_DOC;
  Init;

  HDCfgTraverse(hda.cad,0);
  HDCfgRandomizeXY;
  RedoSprings;
  Fs->draw_it=&DrawIt;
  PopUpOk(
	"This is a tool to cfgure\n"
	"HD Audio.It creates $$FG,RED$$~/HDAudioCfg.HC.Z$$FG$$\n"
	"which you should $$FG,GREEN$$#include$$FG$$ in your\n"
	"$$FG,RED$$~/HomeSnd.HC.Z$$FG$$ file.\n\n\n"
	"Left click to see info and cfgure a widget.\n"
	"Right click drag to connect output to input.\n\n"
	"You will need to set input and output amplifier\n"
	"gains by hand -- edit $$FG,RED$$~/HDAudioCfg.HC.Z$$FG$$.\n\n"
	"The $$FG,BLUE$$BLUE$$FG$$ line in the middle is microphone waveform.\n\n"
	);

  HDRun(TRUE,TRUE); //run input output

  try {
    while (TRUE) {
      switch (GetMsg(&arg1,&arg2,
	    1<<MSG_MS_L_UP|1<<MSG_MS_R_DOWN|1<<MSG_MS_R_UP|1<<MSG_KEY_DOWN)) {
	case MSG_MS_L_UP:
	  if (tmpm1=FindMassByXY(arg1,arg2))
	    HDCfgPopUpInfo(tmpm1);
	  tmpm1=NULL;
	  break;
	case MSG_MS_R_DOWN:
	  tmpm1=FindMassByXY(arg1,arg2);
	  break;
	case MSG_MS_R_UP:
	  tmpm2=FindMassByXY(arg1,arg2);
	  if (tmpm1 && tmpm2)
	    HDCfgEdLink(tmpm1,tmpm2);
	  break;
	case MSG_KEY_DOWN:
	  switch (arg1) {
	    case CH_SPACE:
	      if (tmpm1=FindMassByXY(
		    ms.pos.x-Fs->pix_left-Fs->scroll_x,
		    ms.pos.y-Fs->pix_top-Fs->scroll_y))
		HDCfgPopUpInfo(tmpm1);
	      tmpm1=NULL;
	      break;
	    case '\n':
	      HDCfgRandomizeXY;
	      break;
	    case CH_ESC:
	      HDCfgSave;
	    case CH_SHIFT_ESC:
	      goto hd_done;
	  }
	  break;
      }
    }
hd_done: //Don't goto out of try
    GetMsg(,,1<<MSG_KEY_UP);
  } catch
    Fs->catch_except=TRUE;
  SettingsPop;
  HDStop(TRUE,FALSE); //stop input
  CleanUp;
  MenuPop;
  "$$BK,1$$Note: #include \"~/HDAudioCfg\" in your start-up scripts."
	"$$BK,0$$\n";
}

HDCfg;

