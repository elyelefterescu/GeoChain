import com.android.apksig.ApkSigner;
import com.android.apksig.ApkVerifier;
import java.io.*;
import java.security.*;
import java.security.cert.X509Certificate;
import java.util.*;

// Minimal apksigner replacement: "sign --ks K --ks-pass pass:P --ks-key-alias A [--key-pass pass:P] [--out O] APK" and "verify APK".
public class Signer {
    public static void main(String[] a) throws Exception {
        String ks = null, ksPass = null, alias = null, keyPass = null, out = null, apk = null;
        for (int i = 1; i < a.length; i++) {
            switch (a[i]) {
                case "--ks": ks = a[++i]; break;
                case "--ks-pass": ksPass = a[++i].replaceFirst("^pass:", ""); break;
                case "--ks-key-alias": alias = a[++i]; break;
                case "--key-pass": keyPass = a[++i].replaceFirst("^pass:", ""); break;
                case "--out": out = a[++i]; break;
                case "--verbose": case "-v": break;
                default:
                    if (a[i].startsWith("--")) { if (i + 1 < a.length && !a[i+1].startsWith("--")) i++; }
                    else apk = a[i];
            }
        }
        if (a[0].equals("verify")) {
            ApkVerifier.Result r = new ApkVerifier.Builder(new File(apk)).setMinCheckedPlatformVersion(24).build().verify();
            System.out.println("Verified: " + r.isVerified() + " v1=" + r.isVerifiedUsingV1Scheme() + " v2=" + r.isVerifiedUsingV2Scheme());
            for (Object e : r.getErrors()) System.out.println("ERROR: " + e);
            System.exit(r.isVerified() ? 0 : 1);
        }
        KeyStore store = KeyStore.getInstance(KeyStore.getDefaultType());
        try (InputStream in = new FileInputStream(ks)) { store.load(in, ksPass.toCharArray()); }
        if (alias == null) alias = store.aliases().nextElement();
        PrivateKey key = (PrivateKey) store.getKey(alias, (keyPass != null ? keyPass : ksPass).toCharArray());
        List<X509Certificate> certs = new ArrayList<>();
        for (java.security.cert.Certificate c : store.getCertificateChain(alias)) certs.add((X509Certificate) c);
        ApkSigner.SignerConfig cfg = new ApkSigner.SignerConfig.Builder("CERT", key, certs).build();
        File input = new File(apk);
        File output = out != null ? new File(out) : new File(apk + ".signed.tmp");
        new ApkSigner.Builder(Collections.singletonList(cfg)).setInputApk(input).setOutputApk(output)
            .setMinSdkVersion(24).setV1SigningEnabled(false).setV2SigningEnabled(true).build().sign();
        if (out == null) { input.delete(); output.renameTo(input); }
        System.out.println("Signed");
    }
}
