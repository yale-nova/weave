import java.net.*;
import java.nio.ByteBuffer;
import java.nio.channels.Pipe;
import java.util.Enumeration;

public class GramineNetDebug {
    public static void main(String[] args) {
        System.out.println("=== Gramine Spark Debug Utility ===");

        try {
            // 1. Host and env info
            System.out.println("[Host] Local Hostname: " + InetAddress.getLocalHost().getHostName());
            System.out.println("[Host] Local IP: " + InetAddress.getLocalHost().getHostAddress());
            System.out.println("[Env] SPARK_LOCAL_IP: " + System.getenv("SPARK_LOCAL_IP"));
            System.out.println("[Env] HOSTNAME: " + System.getenv("HOSTNAME"));

            // 2. Network Interfaces
            System.out.println("\n[Net] Enumerating network interfaces:");
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            while (interfaces.hasMoreElements()) {
                NetworkInterface nif = interfaces.nextElement();
                System.out.println("  Interface: " + nif.getName() + " - up=" + nif.isUp());
                Enumeration<InetAddress> addrs = nif.getInetAddresses();
                while (addrs.hasMoreElements()) {
                    System.out.println("    Address: " + addrs.nextElement().getHostAddress());
                }
            }
        } catch (Exception e) {
            System.err.println("[Net] ❌ Network interface error: " + e.getMessage());
            e.printStackTrace();
        }

        try {
            // 3. Resolve and connect to driver
            String driverHost = args.length > 0 ? args[0] : "spark-master";
            int driverPort = args.length > 1 ? Integer.parseInt(args[1]) : 7077;
            System.out.println("\n[RPC] Connecting to driver at " + driverHost + ":" + driverPort);
            InetAddress driverAddr = InetAddress.getByName(driverHost);
            try (Socket s = new Socket(driverAddr, driverPort)) {
                System.out.println("[RPC] ✅ Connected to driver at: " + s.getRemoteSocketAddress());
            }
        } catch (Exception e) {
            System.err.println("[RPC] ❌ Socket connect error: " + e.getMessage());
            e.printStackTrace();
        }

        try {
            // 4. Create Pipe (test PalStreamOpen / memory bookkeeping)
            Pipe pipe = Pipe.open();
            System.out.println("\n[IO] ✅ Pipe opened successfully");
            pipe.source().close();
            pipe.sink().close();
        } catch (Exception e) {
            System.err.println("[IO] ❌ Pipe creation failed: " + e.getMessage());
            e.printStackTrace();
        }

        try {
            // 5. Test direct buffer allocation
            System.out.println("\n[Mem] Allocating 100MB DirectByteBuffer...");
            ByteBuffer buf = ByteBuffer.allocateDirect(100 * 1024 * 1024);
            buf.putInt(0xDEADBEEF);
            System.out.println("[Mem] ✅ DirectByteBuffer allocated and modified");
        } catch (OutOfMemoryError e) {
            System.err.println("[Mem] ❌ DirectByteBuffer OOM: " + e.getMessage());
        }

        try {
            // 6. Stress thread creation
            System.out.println("\n[Thread] Creating test threads...");
            for (int i = 0; i < 1000; i++) {
                final int id = i;
                new Thread(() -> {
                    try { Thread.sleep(10); } catch (InterruptedException ignored) {}
                }, "debug-thread-" + id).start();
            }
            System.out.println("[Thread] ✅ Threads spawned");
        } catch (Throwable t) {
            System.err.println("[Thread] ❌ Thread creation failed: " + t.getMessage());
            t.printStackTrace();
        }

        // 7. Show runtime memory stats
        Runtime rt = Runtime.getRuntime();
        System.out.println("\n[JVM] Memory Info:");
        System.out.printf("  Max: %d MB\n", rt.maxMemory() / (1024 * 1024));
        System.out.printf("  Total: %d MB\n", rt.totalMemory() / (1024 * 1024));
        System.out.printf("  Free: %d MB\n", rt.freeMemory() / (1024 * 1024));

        System.out.println("\n✅ Gramine debug test completed.");
    }
}

