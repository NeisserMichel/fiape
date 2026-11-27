package pe.fiape.app;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/** Fiapé: abre la app web dentro de una app Android. Las fotos del DNI se toman solo con la cámara en vivo
 *  (la app web usa la cámara dentro de la página); no se permite elegir archivos de la galería. */
public class MainActivity extends Activity {
    // Si publicas en otro dominio, cambia HOST y BASE (ver README.md).
    static final String HOST = "neissermichel.github.io";
    static final String BASE = "/fiape";
    static final String HOME = "https://" + HOST + BASE + "/app/index.html";
    static final int CAMARA = 42;
    private WebView web;
    private PermissionRequest pendiente;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(0xFF0B2A63);
        web = new WebView(this);
        setContentView(web);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(false);
        s.setMediaPlaybackRequiresUserGesture(false);   // la vista previa de la cámara empieza sola
        // La app web compara este número con app/version.json y obliga a actualizar si es antiguo
        int version = 0;
        try { version = getPackageManager().getPackageInfo(getPackageName(), 0).versionCode; } catch (Exception e) { /* sin versión */ }
        s.setUserAgentString(s.getUserAgentString() + " Fiape/" + version);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        web.setWebChromeClient(new WebChromeClient() {
            // La página pide la cámara: solo se concede a Fiapé y solo video (nunca micrófono)
            @Override
            public void onPermissionRequest(final PermissionRequest req) {
                runOnUiThread(new Runnable() { @Override public void run() {
                    Uri o = req.getOrigin();
                    boolean propio = o != null && HOST.equals(o.getHost()) && "https".equals(o.getScheme());
                    boolean soloVideo = true;
                    for (String r : req.getResources()) if (!PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(r)) soloVideo = false;
                    if (!propio || !soloVideo) { req.deny(); return; }
                    if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        req.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});
                    } else {
                        if (pendiente != null) pendiente.deny();
                        pendiente = req;
                        requestPermissions(new String[]{Manifest.permission.CAMERA}, CAMARA);
                    }
                }});
            }
            // Sin selector de archivos: las fotos solo se toman con la cámara dentro de la app
            @Override
            public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams params) {
                cb.onReceiveValue(null);
                return true;
            }
        });
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                Uri u = r.getUrl();
                String p = u.getPath();
                if ("https".equals(u.getScheme()) && HOST.equals(u.getHost()) && p != null && p.startsWith(BASE)) return false;
                try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Exception e) { /* sin app para abrirlo */ }
                return true;
            }
            @Override
            public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) {
                if (!r.isForMainFrame()) return;
                String html = "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"
                    + "<body style='font-family:sans-serif;text-align:center;padding:25vh 24px 0;background:#0b2a63;color:#ffffff'>"
                    + "<h2>Sin conexi&oacute;n</h2><p>Revisa tu internet y vuelve a intentar.</p>"
                    + "<a href='" + HOME + "' style='display:inline-block;margin-top:16px;padding:14px 28px;border-radius:14px;"
                    + "background:#f5b700;color:#2b1f00;text-decoration:none;font-weight:bold'>Reintentar</a></body></html>";
                v.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null);
            }
        });
        if (state != null) web.restoreState(state); else web.loadUrl(HOME);
    }

    @Override
    public void onRequestPermissionsResult(int req, String[] perms, int[] res) {
        if (req == CAMARA && pendiente != null) {
            if (res.length > 0 && res[0] == PackageManager.PERMISSION_GRANTED)
                pendiente.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});
            else pendiente.deny();
            pendiente = null;
            return;
        }
        super.onRequestPermissionsResult(req, perms, res);
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) web.goBack(); else super.onBackPressed();
    }
}
