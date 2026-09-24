import java.io.*;
import java.net.InetSocketAddress;
import java.security.KeyStore;
import java.security.cert.X509Certificate;
import java.util.Arrays;
import javax.net.ssl.*;

/**
 * Stand-in TLS peer for the E03-03 spike, used only where the host's `openssl s_server` build
 * (OpenSSL 3.6.4) turned out to reproducibly send a spurious fatal decode_error right after the
 * client's Finished message whenever the peer performing client-cert auth is Android/Conscrypt
 * (a vanilla `openssl s_client` against the same server config completes fine 3/3 times; Android
 * fails 3/3 times) -- see docs/spikes/android-sslsocket-keystore.md for the isolation steps.
 * Accepts any client certificate (trust is out of scope here; the spike's TrustManager work is on
 * the Android side) and just reports what it negotiated.
 *
 * Usage: java JvmTlsServer <port> <protocol: TLSv1.3|TLSv1.2> <requireClientAuth: true|false> <alpn-or-none> <keystore.p12> <password>
 */
public class JvmTlsServer {
    public static void main(String[] args) throws Exception {
        int port = Integer.parseInt(args[0]);
        String protocol = args[1];
        boolean requireClientAuth = Boolean.parseBoolean(args[2]);
        String alpn = args[3];
        String keystorePath = args[4];
        String password = args[5];

        KeyStore keyStore = KeyStore.getInstance("PKCS12");
        try (FileInputStream in = new FileInputStream(keystorePath)) {
            keyStore.load(in, password.toCharArray());
        }
        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(keyStore, password.toCharArray());

        TrustManager trustAnyClient = new X509TrustManager() {
            public void checkClientTrusted(X509Certificate[] chain, String authType) {
                System.out.println("client presented cert: " + chain[0].getSubjectX500Principal());
            }
            public void checkServerTrusted(X509Certificate[] chain, String authType) {}
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
        };

        SSLContext context = SSLContext.getInstance("TLS");
        context.init(kmf.getKeyManagers(), new TrustManager[]{trustAnyClient}, null);

        SSLServerSocketFactory factory = context.getServerSocketFactory();
        SSLServerSocket serverSocket = (SSLServerSocket) factory.createServerSocket();
        serverSocket.setReuseAddress(true);
        serverSocket.bind(new InetSocketAddress(port), 128);
        serverSocket.setEnabledProtocols(new String[]{protocol});
        serverSocket.setNeedClientAuth(requireClientAuth);
        System.out.println("JvmTlsServer listening on :" + port + " protocol=" + protocol
            + " requireClientAuth=" + requireClientAuth + " alpn=" + alpn);
        System.out.flush();

        while (true) {
            SSLSocket socket = (SSLSocket) serverSocket.accept();
            new Thread(() -> handle(socket, alpn)).start();
        }
    }

    private static void handle(SSLSocket socket, String alpn) {
        try {
            if (!alpn.equals("none")) {
                SSLParameters params = socket.getSSLParameters();
                params.setApplicationProtocols(alpn.split(","));
                socket.setSSLParameters(params);
            }
            socket.startHandshake();
            SSLSession session = socket.getSession();
            System.out.println("handshake ok: protocol=" + session.getProtocol()
                + " cipher=" + session.getCipherSuite()
                + " alpn=" + socket.getApplicationProtocol());
            System.out.flush();
        } catch (Exception e) {
            System.out.println("handshake failed: " + e);
            System.out.flush();
        } finally {
            try { socket.close(); } catch (IOException ignored) {}
        }
    }
}
