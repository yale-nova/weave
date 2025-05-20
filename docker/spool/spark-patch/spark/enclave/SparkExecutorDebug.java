import java.io.BufferedReader;
import java.io.FileReader;
import java.lang.reflect.Field;
import java.net.*;
import java.nio.ByteBuffer;
import java.util.Enumeration;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import sun.misc.Unsafe;

public class SparkExecutorDebug {
    public static void main(String[] args) throws Exception {
        System.out.println("=== Spark Executor Debug ===");
        System.out.println("[Args] " + String.join(" ", args));

        String driverHost = null;
        int driverPort = -1;

        // Parse --driver-url
        for (int i = 0; i < args.length; i++) {
            if (args[i].startsWith("--driver-url")) {
                String value = args[i].contains("=") ? args[i].split("=", 2)[1] :
                               (i + 1 < args.length) ? args[i + 1] : null;
                if (value != null) {
                    String[] parts = value.split("@");
                    if (parts.length == 2) {
                        String[] hostPort = parts[1].split(":");
                        if (hostPort.length == 2) {
                            driverHost = hostPort[0];
                            try { driverPort = Integer.parseInt(hostPort[1]); }
                            catch (NumberFormatException e) {
                                System.err.println("❌ Invalid port format: " + hostPort[1]);
                            }
                        }
                    }
                }
            }
        }

        System.out.println("[Parsed] Driver host: " + driverHost);
        System.out.println("[Parsed] Driver port: " + driverPort);

        // Hostname & env
        try {
            String localHostname = InetAddress.getLocalHost().getHostName();
            String localIP = InetAddress.getLocalHost().getHostAddress();
            System.out.println("[Env] HOSTNAME: " + localHostname);
            System.out.println("[Env] Resolved IP: " + localIP);
        } catch (Exception e) {
            System.out.println("❌ Could not resolve local hostname");
            e.printStackTrace();
        }

        System.out.println("[Env] SPARK_LOCAL_IP: " + System.getenv("SPARK_LOCAL_IP"));
        System.out.println("[Env] HOSTNAME (env): " + System.getenv("HOSTNAME"));


        // Attempt driver connect
        if (driverHost != null && driverPort > 0) {
            try {
                System.out.println("[DNS] Resolving " + driverHost + "...");
                InetAddress resolved = InetAddress.getByName(driverHost);
                System.out.println("[DNS] Resolved IP: " + resolved.getHostAddress());

                System.out.println("[NET] Attempting TCP connect to " + driverHost + ":" + driverPort + "...");
                Socket s = new Socket(resolved, driverPort);
                System.out.println("[NET] ✅ Successfully connected to driver!");
                s.close();
            } catch (Exception e) {
                System.out.println("[NET] ❌ Failed to connect to driver: " + e.getMessage());
                e.printStackTrace();
            }
        }

        // Dump basic system info
        System.out.println("[SYS] Runtime Info:");
        System.out.println("  Max JVM Memory: " + Runtime.getRuntime().maxMemory() / (1024 * 1024) + " MB");
        System.out.println("  Available Processors: " + Runtime.getRuntime().availableProcessors());

        // /proc/meminfo
        try (BufferedReader br = new BufferedReader(new FileReader("/proc/meminfo"))) {
            System.out.println("[SYS] /proc/meminfo snapshot:");
            for (int i = 0; i < 10; i++) {
                System.out.println("  " + br.readLine());
            }
        } catch (Exception e) {
            System.out.println("❌ Cannot read /proc/meminfo");
        }

        // /dev/random test
        try {
            System.out.println("[DEV] Testing /dev/urandom access...");
            new java.io.FileInputStream("/dev/urandom").read();
            System.out.println("  ✅ /dev/urandom accessible");
        } catch (Exception e) {
            System.out.println("  ❌ /dev/urandom not accessible: " + e.getMessage());
        }

        // Allocate Unsafe memory
        try {
            System.out.println("[MEM] Unsafe.allocateMemory test...");
            Field f = Unsafe.class.getDeclaredField("theUnsafe");
            f.setAccessible(true);
            Unsafe unsafe = (Unsafe) f.get(null);
            long ptr = unsafe.allocateMemory(1024 * 1024);
            unsafe.setMemory(ptr, 1024 * 1024, (byte) 0);
            System.out.println("  ✅ Unsafe memory allocated and zeroed.");
            unsafe.freeMemory(ptr);
        } catch (Throwable t) {
            System.out.println("  ❌ Unsafe.allocateMemory failed: " + t);
        }

        // Spawn 10 threads that allocate memory
        System.out.println("[MEM] Testing direct buffer allocation in 10 threads...");
        CountDownLatch latch = new CountDownLatch(10);
        for (int i = 0; i < 10; i++) {
            final int tid = i;
            new Thread(() -> {
                try {
                    ByteBuffer buf = ByteBuffer.allocateDirect(10 * 1024 * 1024);
                    System.out.println("[Thread " + tid + "] ✅ Direct buffer allocated.");
                } catch (Throwable t) {
                    System.out.println("[Thread " + tid + "] ❌ Allocation failed: " + t);
                } finally {
                    latch.countDown();
                }
            }).start();
        }

        latch.await();

        
	// List interfaces
        try {
            System.out.println("[NET] Listing interfaces:");
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            while (interfaces.hasMoreElements()) {
                NetworkInterface ni = interfaces.nextElement();
                System.out.println("  Interface: " + ni.getName() + " (Up=" + ni.isUp() + ")");
                Enumeration<InetAddress> addrs = ni.getInetAddresses();
                while (addrs.hasMoreElements()) {
                    System.out.println("    " + addrs.nextElement().getHostAddress());
                }
            }
        } catch (Exception e) {
            System.out.println("❌ Error listing interfaces");
            e.printStackTrace();
        }

	// Dump selected env vars
        System.out.println("[Env] Listing some env vars:");
        for (Map.Entry<String, String> e : System.getenv().entrySet()) {
            if (e.getKey().toLowerCase().contains("spark") || e.getKey().toLowerCase().contains("gramine"))
                System.out.println("  " + e.getKey() + "=" + e.getValue());
        }

        System.out.println("=== Done ===");
    }
}

