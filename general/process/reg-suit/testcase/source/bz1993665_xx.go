package main
import (
    "os"
    "syscall"
    "runtime"
)
func main() {
    runtime.LockOSThread()
    syscall.Exec("/bin/echo", []string{"/bin/echo", "Hello"}, os.Environ())
}
