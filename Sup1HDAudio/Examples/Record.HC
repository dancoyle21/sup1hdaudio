Bool record_stop,record_done;

U0 (*fp_old_copy_buf)(SND_IN_CONTAINER *buf,I64 buf_num)=NULL;

#define RECORD_BUF_SIZE	(SND_BUF_LEN*0x100)

SND_IN_CONTAINER *record_buf[2];
I64 record_buf_iptr,record_ibuf_num,record_obuf_num;

U0 RecordCopyBuf(SND_IN_CONTAINER *buf,I64)
{
  I64 j;
  SND_IN_CONTAINER *_s=record_buf[record_ibuf_num&1];
  j=0;
  while (j<SND_BUF_LEN) {
    _s[record_buf_iptr++]=buf[j++];
    j++; //Record in mono
  }
  if (record_buf_iptr>=RECORD_BUF_SIZE) {
    record_buf_iptr=0;
    record_ibuf_num++;
  }
}

U0 DrawIt(CTask *task,CDC *dc)
{
  SND_IN_CONTAINER *buf=hda.istr0_buf[0];
  I64 i,x1,y1,x2=0,y2=0,
	cy=task->pix_height>>1;
  dc->color=BLUE;
  for (i=0;i<SND_BUF_LEN;i++) {
    x1=i*task->pix_width/SND_BUF_LEN;
    y1=cy-buf[i]*cy/I16_MAX;
    GrLine(dc,x2,y2,x1,y1);
    x2=x1;
    y2=y1;
  }
  dc->color=RED;
}

U0 RecordTaskEndCB()
{
  fp_snd_copy_buf=fp_old_copy_buf;
  HDStop(TRUE,FALSE);
  Free(record_buf[0]);
  Free(record_buf[1]);
  record_done=TRUE;
  Exit;
}

U0 RecordTask(U8 *filename)
{
  Bool old_io_snd;
  U8 *filename=StrNew(filename),*filename2;
  TaskInitExt; //needed for disk access
  record_buf[0]=CAlloc(RECORD_BUF_SIZE*sizeof(SND_IN_CONTAINER));
  record_buf[1]=CAlloc(RECORD_BUF_SIZE*sizeof(SND_IN_CONTAINER));
  FileExtRem(filename);
  record_buf_iptr=0;
  record_ibuf_num=0;
  record_obuf_num=0;
  record_done=FALSE;
  Fs->task_end_cb=&RecordTaskEndCB;
  fp_old_copy_buf=fp_snd_copy_buf;
  fp_snd_copy_buf=&RecordCopyBuf;
  HDRun(TRUE,FALSE);
  old_io_snd=IOSnd(OFF);
  while (!record_stop) {
    if (record_ibuf_num>record_obuf_num) {
      filename2=MPrint("%s%04d.SNZ",filename,record_obuf_num);
      SndFileWrite(filename2,record_buf[record_obuf_num&1],RECORD_BUF_SIZE);
      record_obuf_num++;
      Free(filename2);
    }
    Sleep(1);
  }
  filename2=MPrint("%s%04d.SNZ",filename,record_obuf_num);
  SndFileWrite(filename2,record_buf[record_obuf_num&1],record_buf_iptr);
  record_obuf_num++;
  Free(filename2);
  Free(filename);
  IOSnd(old_io_snd);
  record_done=TRUE;
}

U0 RecordDemo(U8 *filename="~/Record.SNZ")
{
  if (snd_dev!=SD_HD_AUDIO) {
    "Only works for HD Audio.\n";
    return;
  }
  record_done=FALSE;
  record_stop=FALSE;
  Spawn(&RecordTask,filename,"Record .SNZ",,Fs);
  SettingsPush; //See $LK,"SettingsPush",A="MN:SettingsPush"$
  DocCursor;
  DocClear;
  Fs->draw_it=&DrawIt;
  try
	  GetChar;
  catch //Catch <CTRL-ALT-C>, but pass it on to next higher hndlr.
    record_stop=TRUE;
  record_stop=TRUE;
  while (record_done)
    Yield;
  SettingsPop;
  while (TRUE) {
    "\n\nPlay ";
    if (YorN)
      SndFilePlaySeq(filename,record_obuf_num);
    else
      break;
  }
  NewLine(2);
}

RecordDemo;
