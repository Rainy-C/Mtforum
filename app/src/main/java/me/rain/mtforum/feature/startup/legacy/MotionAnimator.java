package me.rain.mtforum.feature.startup.legacy;

import android.animation.Animator;
import android.animation.AnimatorSet;
import android.animation.ObjectAnimator;
import android.animation.TimeInterpolator;
import android.view.View;

import java.util.ArrayList;
import java.util.List;

public final class MotionAnimator {
    private static final TimeInterpolator SINE_OUT = t -> (float) Math.sin(t * Math.PI / 2.0);
    private static final TimeInterpolator CUBIC_OUT = t -> 1f - (1f - t) * (1f - t) * (1f - t);

    private final View icon;
    private final View wordmark;
    private final View next;
    private AnimatorSet current;

    public MotionAnimator(View icon, View wordmark, View next) {
        this.icon = icon;
        this.wordmark = wordmark;
        this.next = next;
    }

    public void play() {
        cancel();
        List<Animator> animators = new ArrayList<>();
        addLogo(animators, icon);
        addLogo(animators, wordmark);

        next.setVisibility(View.VISIBLE);
        next.setAlpha(0f);
        next.setScaleX(0.9f);
        next.setScaleY(0.9f);
        animators.add(animate(next, View.ALPHA, 0f, 1f, 1340L, 450L, CUBIC_OUT));
        animators.add(animate(next, View.SCALE_X, 0.9f, 1f, 1340L, 450L, CUBIC_OUT));
        animators.add(animate(next, View.SCALE_Y, 0.9f, 1f, 1340L, 450L, CUBIC_OUT));

        current = new AnimatorSet();
        current.playTogether(animators);
        current.start();
    }

    private static void addLogo(List<Animator> animators, View view) {
        view.setVisibility(View.VISIBLE);
        view.setAlpha(0f);
        view.setScaleX(0.5f);
        view.setScaleY(0.5f);
        animators.add(animate(view, View.SCALE_X, 0.5f, 0.95f, 0L, 440L, SINE_OUT));
        animators.add(animate(view, View.SCALE_Y, 0.5f, 0.95f, 0L, 440L, SINE_OUT));
        animators.add(animate(view, View.SCALE_X, 0.95f, 1f, 440L, 700L, CUBIC_OUT));
        animators.add(animate(view, View.SCALE_Y, 0.95f, 1f, 440L, 700L, CUBIC_OUT));
        animators.add(animate(view, View.ALPHA, 0f, 1f, 60L, 440L, CUBIC_OUT));
    }

    private static ObjectAnimator animate(View view, android.util.Property<View, Float> property,
                                           float from, float to, long delay, long duration,
                                           TimeInterpolator easing) {
        ObjectAnimator animator = ObjectAnimator.ofFloat(view, property, from, to);
        animator.setStartDelay(delay);
        animator.setDuration(duration);
        animator.setInterpolator(easing);
        return animator;
    }

    public void pause() {
        if (current != null && current.isStarted()) current.pause();
    }

    public void resume() {
        if (current != null && current.isPaused()) current.resume();
    }

    public void cancel() {
        if (current != null) {
            current.cancel();
            current = null;
        }
    }
}

