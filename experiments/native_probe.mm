#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <cstdio>
#include <string>
#include <vector>
int main(int argc,char**argv) { @autoreleasepool {
 void *h=dlopen("/Library/Input Methods/DoubaoIme.app/Contents/Frameworks/OimeEngine.framework/Versions/A/OimeEngine",RTLD_NOW|RTLD_LOCAL);
 if(!h){fprintf(stderr,"%s\n",dlerror());return 2;}
 NSString *mode=@(argv[1]);
 if([mode isEqual:@"cpp"]){
 auto create=(void*(*)(int))dlsym(h,"_ZN11oime_engine12CreateEngineENS_10EngineTypeE");
 auto load=(int(*)(void*,NSString*,int,void*))dlsym(h,"_ZN15oime_engine_ios16LoadDictIfNeededEPN11oime_engine15EngineInterfaceEP8NSStringNS_21ImeEngineDictLoadTypeERNSt3__16vectorINS0_8FdErrMsgENS6_9allocatorIS8_EEEE");
 auto save=(bool(*)(void*,bool,void*))dlsym(h,"_ZN11oime_engine6pinyin6Engine11SaveUsrDictEbRNSt3__16vectorINS_8FdErrMsgENS2_9allocatorIS4_EEEE");
 auto count=(unsigned(*)(const std::vector<int>&,const std::string&))dlsym(h,"_ZN11oime_engine19GetUsrDictItemCountERKNSt3__16vectorINS_10EngineTypeENS0_9allocatorIS2_EEEERKNS0_12basic_stringIcNS0_11char_traitsIcEENS3_IcEEEE");
 if(!create||!load||!save)return 8;
 void *engine=create(0); void *errors[3]={};
 int s=load(engine,@"/Library/Input Methods/DoubaoIme.app/Contents/Frameworks/OimeEngine.framework/Versions/A/Resources/OimeEngineResources.bundle",0,errors);
 int u=load(engine,@(argv[2]),1,errors);
 printf("sys_load=%d user_load=%d error_bytes=%ld\n",s,u,(long)((char*)errors[1]-(char*)errors[0]));
 if(argc>3)printf("saved=%d\n",save(engine,false,errors));
 if(count)printf("native_count=%u\n",count(std::vector<int>{0},std::string(argv[2])));
 fflush(stdout);_Exit(u==1?9:0);
 }
 if([mode isEqual:@"map"]){
 auto f=(bool(*)(const char*,unsigned short,unsigned short&))dlsym(h,"_ZN11oime_engine18PinyinToSyllableIdEPKctRt");
 if(!f)return 3;
 NSArray *keys=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] options:0 error:nil];
 NSMutableDictionary *out=[NSMutableDictionary dictionary];
 for(NSString *s in keys){unsigned short value=65535; bool ok=f(s.UTF8String,(unsigned short)strlen(s.UTF8String),value);out[s]=@[@(ok),@(value)];}
 [[NSJSONSerialization dataWithJSONObject:out options:0 error:nil] writeToFile:@(argv[3]) atomically:YES];
 printf("mapped %lu symbols\n",(unsigned long)out.count);return 0;
 }
 Class c=objc_getClass("ImeEngine");if(!c)return 4;
 if([mode isEqual:@"methods"]){for(int kind=0;kind<2;kind++){unsigned n=0;Method *ms=class_copyMethodList(kind?object_getClass(c):c,&n);for(unsigned i=0;i<n;i++)printf("%c %s %s\n",kind?'+':'-',sel_getName(method_getName(ms[i])),method_getTypeEncoding(ms[i]));free(ms);}return 0;}
 id obj=[[c alloc] init];
 auto call=(BOOL(*)(id,SEL,id,id))objc_msgSend;
 NSString *dir=@(argv[2]);
 NSString *sys=@"/Library/Input Methods/DoubaoIme.app/Contents/Frameworks/OimeEngine.framework/Versions/A/Resources/OimeEngineResources.bundle";
 ((char(*)(id,SEL,id))objc_msgSend)(obj,sel_registerName("setStoragePath:"),dir);
 printf("create_result=%d\n",((BOOL(*)(id,SEL,long,id,id))objc_msgSend)(obj,sel_registerName("createInputEngine:sysDictPath:userDictPath:"),argc>3?atol(argv[3]):0,sys,dir));
 ((void(*)(id,SEL,long,id,id))objc_msgSend)(obj,sel_registerName("launchEngine:sysDictPath:userDictPath:"),argc>3?atol(argv[3]):0,sys,dir);
 void *engine=((void*(*)(id,SEL,id,id))objc_msgSend)(obj,sel_registerName("loadEngineWithSysDictPath:userDictPath:"),sys,dir);
 printf("engine_created=%d\n",engine!=nullptr);
 if(!engine)return 5;
 BOOL loaded=((BOOL(*)(id,SEL,id))objc_msgSend)(obj,sel_registerName("loadUsrDict:"),dir);
 printf("user_dict_loaded=%d\n",loaded);
 if([mode isEqual:@"learn"]){
 id converted=((id(*)(id,SEL,id,id))objc_msgSend)(obj,sel_registerName("convert::"),@"ci\'du\'qian\'yi\'yan\'zheng\'ci",nil);
 id candidate=[[converted valueForKey:@"candidates"] firstObject];
 ((id(*)(id,SEL,id,id))objc_msgSend)(obj,sel_registerName("learnCandidatePinyin:Word:"),@"ciduqianyiyanzhengci",candidate);
 printf("saved_after_learning=%d\n",((BOOL(*)(id,SEL,BOOL))objc_msgSend)(obj,sel_registerName("saveUsrDict:"),NO));
 }
 if([mode isEqual:@"query"]){
 NSArray *entries=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[4])] options:0 error:nil];
 ((void(*)(id,SEL,long))objc_msgSend)(obj,sel_registerName("setPageSize:"),100);
 NSMutableArray *results=[NSMutableArray array];
 for(NSDictionary *entry in entries){
 id r=((id(*)(id,SEL,id,id))objc_msgSend)(obj,sel_registerName("convert::"),entry[@"pinyin"],nil);
 NSArray *candidates=[r valueForKey:@"candidates"];
 if(argc>6){id syllables=[r valueForKey:@"syllables"]; NSMutableArray *ss=[NSMutableArray array]; for(id sy in syllables)[ss addObject:@{@"class":NSStringFromClass([sy class]),@"value":[sy description]}]; [[NSJSONSerialization dataWithJSONObject:ss options:0 error:nil] writeToFile:@(argv[6]) atomically:YES];}
 BOOL found=NO; for(id candidate in candidates){for(NSString *key in @[@"word_",@"displayString_",@"commitWord_"]){if([[candidate valueForKey:key] isEqual:entry[@"word"]]) found=YES;}}
 NSString *desc=@"";
 [results addObject:@{@"found":@(found),@"class":NSStringFromClass([r class])?:@"nil",@"candidates":@(candidates.count)}];
 ((void(*)(id,SEL))objc_msgSend)(obj,sel_registerName("clearCache"));
 }
 [[NSJSONSerialization dataWithJSONObject:results options:0 error:nil] writeToFile:@(argv[5]) atomically:YES];
 printf("queried=%lu found=%lu\n",(unsigned long)results.count,(unsigned long)[results filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"found == YES"]].count);
 }
 ((void(*)(id,SEL,id))objc_msgSend)(obj,sel_registerName("exportUserDict:"),[dir stringByAppendingPathComponent:@"export"]);
 if([mode isEqual:@"save"])printf("saved=%d\n",((BOOL(*)(id,SEL,BOOL))objc_msgSend)(obj,sel_registerName("saveUsrDict:"),NO));
 return loaded?0:6;
}}
