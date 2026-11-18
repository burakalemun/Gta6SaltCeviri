package com.saltceviri.tv;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String url = getIntent().getStringExtra("server_url");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Intent permIntent = new Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + getPackageName())
            );
            startActivity(permIntent);
        } else {
            Intent svc = new Intent(this, SubtitleOverlayService.class);
            if (url != null && !url.isEmpty()) {
                svc.putExtra("server_url", url);
            }
            startService(svc);
        }
        finish();
    }
}
