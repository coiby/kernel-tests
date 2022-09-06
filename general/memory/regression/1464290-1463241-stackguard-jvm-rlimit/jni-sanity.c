#include <jni.h>

int main(int argc, char *args[]) {
     JavaVM *jvm;
     JNIEnv *env;
     JavaVMInitArgs vm_args;
     JavaVMOption options [1];
     options[0].optionString = "-Djava.class.path=/usr/lib/java";
     vm_args.version = JNI_VERSION_1_6;
     vm_args.nOptions = 1;
     vm_args.options = options;
     vm_args.ignoreUnrecognized = 0;

     JNI_CreateJavaVM(&jvm, (void**)&env, &vm_args); //crash at this line
            /**............**/

     (*jvm)->DestroyJavaVM(jvm);
            return 0;
}
