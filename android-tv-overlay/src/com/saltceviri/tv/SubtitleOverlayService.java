package com.saltceviri.tv;

import android.app.Service;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;

public class SubtitleOverlayService extends Service {
    private WindowManager windowManager;
    private LinearLayout container;
    private TextView subtitleView;
    private TextView englishView;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private volatile boolean running = true;
    private String serverUrl = "";
    private int lastSeq = -1;

    @Override
    public void onCreate() {
        super.onCreate();
        SharedPreferences prefs = getSharedPreferences("saltceviri", MODE_PRIVATE);
        serverUrl = prefs.getString("server_url", "");
        setupOverlayView();
        startPollingThread();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && intent.hasExtra("server_url")) {
            String u = intent.getStringExtra("server_url");
            if (u != null && !u.trim().isEmpty()) {
                serverUrl = u.trim();
                getSharedPreferences("saltceviri", MODE_PRIVATE)
                    .edit()
                    .putString("server_url", serverUrl)
                    .apply();
            }
        }
        return START_STICKY;
    }

    private void setupOverlayView() {
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        container = new LinearLayout(this);
        container.setOrientation(LinearLayout.VERTICAL);
        container.setGravity(Gravity.CENTER_HORIZONTAL);
        container.setPadding(36, 16, 36, 16);
        container.setVisibility(View.GONE);

        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.argb(218, 8, 10, 16));
        bg.setCornerRadius(20f);
        bg.setStroke(2, Color.argb(60, 255, 255, 255));
        container.setBackground(bg);

        subtitleView = new TextView(this);
        subtitleView.setTextColor(Color.WHITE);
        subtitleView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        subtitleView.setTypeface(Typeface.DEFAULT_BOLD);
        subtitleView.setGravity(Gravity.CENTER);
        subtitleView.setShadowLayer(4f, 0f, 2f, Color.BLACK);
        container.addView(subtitleView);

        englishView = new TextView(this);
        englishView.setTextColor(Color.LTGRAY);
        englishView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        englishView.setGravity(Gravity.CENTER);
        englishView.setVisibility(View.GONE);
        container.addView(englishView);

        int overlayType = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            : WindowManager.LayoutParams.TYPE_SYSTEM_ALERT;

        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        );
        params.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
        params.y = 48;

        windowManager.addView(container, params);
    }

    private void startPollingThread() {
        new Thread(() -> {
            while (running) {
                if (serverUrl != null && !serverUrl.isEmpty()) {
                    try {
                        URL url = new URL(serverUrl);
                        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                        conn.setConnectTimeout(1500);
                        conn.setReadTimeout(1500);
                        if (conn.getResponseCode() == 200) {
                            BufferedReader br = new BufferedReader(new InputStreamReader(conn.getInputStream()));
                            StringBuilder sb = new StringBuilder();
                            String line;
                            while ((line = br.readLine()) != null) sb.append(line);
                            br.close();

                            JSONObject obj = new JSONObject(sb.toString());
                            int seq = obj.optInt("seq", -1);
                            if (seq != lastSeq) {
                                lastSeq = seq;
                                final String spk = obj.optString("speaker", "");
                                final String tr = obj.optString("turkish_text", "");
                                final String en = obj.optString("english_text", "");
                                final boolean showEn = obj.optBoolean("show_original", false);

                                mainHandler.post(() -> updateSubtitleUI(spk, tr, en, showEn));
                            }
                        }
                        conn.disconnect();
                    } catch (Exception ignored) { }
                }
                try { Thread.sleep(120); } catch (InterruptedException ignored) { }
            }
        }).start();
    }

    private void updateSubtitleUI(String speaker, String tr, String en, boolean showEn) {
        if (tr == null || tr.trim().isEmpty()) {
            container.setVisibility(View.GONE);
            return;
        }
        container.setVisibility(View.VISIBLE);
        if (speaker != null && !speaker.isEmpty()) {
            subtitleView.setText(speaker + ": " + tr);
            if ("LUCIA".equalsIgnoreCase(speaker)) {
                subtitleView.setTextColor(Color.parseColor("#FF5C94"));
            } else if ("JASON".equalsIgnoreCase(speaker)) {
                subtitleView.setTextColor(Color.parseColor("#38D1FA"));
            } else {
                subtitleView.setTextColor(Color.parseColor("#FFD147"));
            }
        } else {
            subtitleView.setText(tr);
            subtitleView.setTextColor(Color.WHITE);
        }
        if (showEn && en != null && !en.isEmpty()) {
            englishView.setText(en);
            englishView.setVisibility(View.VISIBLE);
        } else {
            englishView.setVisibility(View.GONE);
        }
    }

    @Override
    public void onDestroy() {
        running = false;
        if (windowManager != null && container != null) {
            try { windowManager.removeView(container); } catch (Exception ignored) { }
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
