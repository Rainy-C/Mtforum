/* Based on HyperCeiler GlowController.java, AGPL-3.0; see NOTICE and LICENSE. */
package com.sevtinge.hyperceiler.provision.renderengine;

import android.view.View;

public final class GlowController implements Runnable {
    private GlowPainter painter;
    private float time;
    private float direction = 1f;
    private long previousFrame;
    private boolean frozen;
    private final View target;

    public GlowController(View view) { target = view; }

    public void start(boolean entrance) {
        if (painter != null) return;
        painter = new GlowPainter(target.getContext());
        painter.needAdmission(entrance);
        time = 0f;
        direction = 1f;
        previousFrame = System.nanoTime();
        frozen = false;
        target.post(this);
    }

    @Override public void run() {
        if (painter == null || frozen) return;
        long now = System.nanoTime();
        float dt = Math.min(0.06f, Math.max(0f, (now - previousFrame) * 1e-9f));
        previousFrame = now;
        time += dt * direction;
        if (direction > 0f && time >= 120f) direction = -1f;
        else if (direction < 0f && time <= 2f) direction = 1f;
        if (target.getWidth() <= 0 || target.getHeight() <= 0) {
            target.postDelayed(this, 16L);
            return;
        }
        painter.setAnimTime(time);
        painter.setResolution(target.getWidth(), target.getHeight());
        target.setRenderEffect(painter.getRenderEffect());
        target.postDelayed(this, 16L);
    }

    /** Leave the last shader frame visible so the translucent next page can shrink back onto it. */
    public void freeze() {
        frozen = true;
        target.removeCallbacks(this);
    }

    public void thaw() {
        if (painter == null || !frozen) return;
        previousFrame = System.nanoTime();
        frozen = false;
        target.post(this);
    }

    public void resetTime() {
        time = 0f;
        previousFrame = System.nanoTime();
    }

    public void setCircleYOffset(float value) {
        if (painter != null) painter.setCircleYOffset(value);
    }

    public void setCircleYOffsetWithView(View view, View background) {
        if (painter == null || view == null || background == null || background.getHeight() <= 0) return;
        int[] position = new int[2];
        view.getLocationOnScreen(position);
        int centerY = position[1] + view.getHeight() / 2;
        setCircleYOffset((background.getHeight() / 2f - centerY) / background.getHeight());
    }

    public void stop() {
        frozen = false;
        target.removeCallbacks(this);
        if (painter == null) return;
        painter = null;
        target.setRenderEffect(null);
    }
}

