import java.net.InetAddress;

public class DnsTest {
    public static void main(String[] args) {
        if (args.length == 0) {
            System.out.println("⚠️  Usage: java DnsTest <hostname1> <hostname2> ...");
            return;
        }

        for (String host : args) {
            try {
                InetAddress inet = InetAddress.getByName(host);
                System.out.println("✅ " + host + " resolved to " + inet.getHostAddress());
            } catch (Exception e) {
                System.out.println("❌ " + host + " could not be resolved: " + e.getMessage());
            }
        }
    }
}
