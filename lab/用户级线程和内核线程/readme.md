```Bash
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/syscall.h>

#define gettid() syscall(__NR_gettid)

pthread_t ntid;

void *printids(void *s)
{
    pid_t pid;  // 进程号
    pid_t ktid; // 内核级线程号
    pthread_t utid; // 用户级线程号

    pid = getpid(); // 获取当前进程号
    ktid = gettid(); // 获取内核级线程号
    utid = pthread_self(); // 获取用户级线程号

    printf("%s pid %u ktid %u utid %u (0x%x)\n", s, (unsigned int)pid, (unsigned int)ktid,
            (unsigned int)utid, (unsigned int) utid);
    pause();
}

int main(void) // 主线程
{
    // 主线程main() 调用pthread_create创建一个子线程
    pthread_create(&ntid, NULL, printids, "new thread:");
    // 主线程main() 调用printids 打印自己的线程号和所属进程号
    printids("main thread:");
    sleep(1);
    return 0;
}
```

编译线程：gcc thread_ex.c -o thread_ex -lpthread

运行：./thread_ex

![](result.png)