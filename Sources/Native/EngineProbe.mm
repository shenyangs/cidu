#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <cstdio>
#include <string>
#include <vector>
int main(int argc,char**argv) { @autoreleasepool {
 if(argc < 3) return 64;
 void *h=dlopen("/Library/Input Methods/DoubaoIme.app/Contents/Frameworks/OimeEngine.framework/Versions/A/OimeEngine",RTLD_NOW|RTLD_LOCAL);
 if(!h) return 2;
 NSString *mode=@(argv[1]);
 if([mode isEqual:@"cpp"]){
 if(argc != 4)return 64;
 auto create=(void*(*)(int))dlsym(h,"_ZN11oime_engine12CreateEngineENS_10EngineTypeE");
 auto load=(int(*)(void*,NSString*,int,void*))dlsym(h,"_ZN15oime_engine_ios16LoadDictIfNeededEPN11oime_engine15EngineInterfaceEP8NSStringNS_21ImeEngineDictLoadTypeERNSt3__16vectorINS0_8FdErrMsgENS6_9allocatorIS8_EEEE");
 auto count=(unsigned(*)(const std::vector<int>&,const std::string&))dlsym(h,"_ZN11oime_engine19GetUsrDictItemCountERKNSt3__16vectorINS_10EngineTypeENS0_9allocatorIS2_EEEERKNS0_12basic_stringIcNS0_11char_traitsIcEENS3_IcEEEE");
 if(!create||!load||!count)return 8;
 void *engine=create(0); if(!engine)return 8; void *errors[3]={};
 int s=load(engine,@"/Library/Input Methods/DoubaoIme.app/Contents/Frameworks/OimeEngine.framework/Versions/A/Resources/OimeEngineResources.bundle",0,errors);
 int u=load(engine,@(argv[2]),1,errors);
 unsigned actual=count(std::vector<int>{0},std::string(argv[2]));
 BOOL written=[[@(actual) stringValue] writeToFile:@(argv[3]) atomically:YES encoding:NSUTF8StringEncoding error:nil];
 long errorBytes=(long)((char*)errors[1]-(char*)errors[0]);
 BOOL diagnostic=[[@(errorBytes) stringValue] writeToFile:[@(argv[3]) stringByAppendingString:@".errors"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 _Exit(s==0 && u==0 && written && diagnostic ? 0:9);
 }
 if([mode isEqual:@"map"]){
 if(argc!=4)return 64;
 auto f=(bool(*)(const char*,unsigned short,unsigned short&))dlsym(h,"_ZN11oime_engine18PinyinToSyllableIdEPKctRt");
 if(!f)return 3;
 NSArray *keys=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] options:0 error:nil];
 if(![keys isKindOfClass:[NSArray class]])return 64;
 NSMutableDictionary *out=[NSMutableDictionary dictionary];
 for(NSString *s in keys){if(![s isKindOfClass:[NSString class]] || strlen(s.UTF8String)>65535)return 64; unsigned short value=65535; bool ok=f(s.UTF8String,(unsigned short)strlen(s.UTF8String),value);out[s]=@[@(ok),@(value)];}
 if(![[NSJSONSerialization dataWithJSONObject:out options:0 error:nil] writeToFile:@(argv[3]) atomically:YES])return 7;
 printf("mapped %lu symbols\n",(unsigned long)out.count);return 0;
 }
 return 64;
}}
