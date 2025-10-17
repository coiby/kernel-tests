import java.lang.Thread;

public class Fib extends Thread {
    public void run() {
        return ;
    }
    private static long fib(int n) {
        try {
            Thread.sleep(1000);
        } catch (Exception e) {
        }
        Fib rh = new Fib();
        rh.start();
        if (n < 2) return 1;
        return fib(n-1) + fib(n-2);
    }

    public static void main(String[] args) {
        System.out.println(fib(100));
    }
}
