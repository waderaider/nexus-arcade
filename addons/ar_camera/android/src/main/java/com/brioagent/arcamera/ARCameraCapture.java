package com.brioagent.arcamera;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.ImageFormat;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;

import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * Single-shot Camera2 capture for Quest 3 passthrough RGB cameras.
 * Meta's Passthrough Camera API is itself built on Camera2; the outward-facing
 * RGB cameras are exposed as Camera2 devices. We prefer LENS_FACING_BACK
 * (outward on Quest), then FRONT, then the first available device.
 * Every failure path returns null so GDScript can fall back gracefully.
 */
public class ARCameraCapture {
    private static final String TAG = "ARCamera";
    private static final int CAPTURE_W = 1280;
    private static final int CAPTURE_H = 720;
    private static final long TIMEOUT_MS = 5000;

    private final Context context;
    private volatile byte[] lastJpeg = null;
    private volatile int lastW = 0;
    private volatile int lastH = 0;

    public ARCameraCapture(Context context) {
        this.context = context.getApplicationContext();
    }

    public boolean hasCameraPermission() {
        return context.checkSelfPermission(Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED;
    }

    public void requestPermission(Activity activity) {
        if (activity == null || hasCameraPermission()) return;
        activity.requestPermissions(new String[]{Manifest.permission.CAMERA}, 1001);
    }

    /** True when a usable camera device exists (permission checked separately). */
    public boolean isAvailable() {
        try {
            CameraManager cm = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
            return chooseCameraId(cm) != null;
        } catch (Exception e) {
            Log.w(TAG, "isAvailable failed", e);
            return false;
        }
    }

    /** Blocking single JPEG capture. Returns null on any failure/timeout. */
    public byte[] captureJpeg() {
        lastJpeg = null;
        if (!hasCameraPermission()) {
            Log.w(TAG, "captureJpeg: no CAMERA permission");
            return null;
        }
        HandlerThread thread = new HandlerThread("ARCameraBg");
        thread.start();
        Handler bg = new Handler(thread.getLooper());
        final CountDownLatch latch = new CountDownLatch(1);
        final byte[][] out = new byte[1][];
        try {
            CameraManager cm = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
            String cameraId = chooseCameraId(cm);
            if (cameraId == null) return null;

            final ImageReader reader =
                    ImageReader.newInstance(CAPTURE_W, CAPTURE_H, ImageFormat.JPEG, 2);
            reader.setOnImageAvailableListener(r -> {
                Image img = null;
                try {
                    img = r.acquireLatestImage();
                    if (img != null) {
                        ByteBuffer buf = img.getPlanes()[0].getBuffer();
                        byte[] data = new byte[buf.remaining()];
                        buf.get(data);
                        out[0] = data;
                        lastW = img.getWidth();
                        lastH = img.getHeight();
                    }
                } catch (Exception e) {
                    Log.w(TAG, "image read failed", e);
                } finally {
                    if (img != null) img.close();
                    latch.countDown();
                }
            }, bg);

            final CameraDevice[] deviceHolder = new CameraDevice[1];
            final CountDownLatch openLatch = new CountDownLatch(1);
            cm.openCamera(cameraId, new CameraDevice.StateCallback() {
                @Override public void onOpened(CameraDevice camera) {
                    deviceHolder[0] = camera;
                    openLatch.countDown();
                }
                @Override public void onDisconnected(CameraDevice camera) {
                    camera.close();
                    openLatch.countDown();
                    latch.countDown();
                }
                @Override public void onError(CameraDevice camera, int error) {
                    camera.close();
                    openLatch.countDown();
                    latch.countDown();
                }
            }, bg);
            if (!openLatch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS) || deviceHolder[0] == null) {
                reader.close();
                return null;
            }
            final CameraDevice device = deviceHolder[0];
            final CountDownLatch sessionLatch = new CountDownLatch(1);
            device.createCaptureSession(Arrays.asList(reader.getSurface()),
                    new CameraCaptureSession.StateCallback() {
                        @Override public void onConfigured(CameraCaptureSession session) {
                            try {
                                CaptureRequest.Builder b =
                                        device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
                                b.addTarget(reader.getSurface());
                                b.set(CaptureRequest.CONTROL_MODE,
                                        CaptureRequest.CONTROL_MODE_AUTO);
                                session.capture(b.build(),
                                        new CameraCaptureSession.CaptureCallback() {}, bg);
                            } catch (CameraAccessException e) {
                                Log.w(TAG, "capture failed", e);
                                latch.countDown();
                            }
                            sessionLatch.countDown();
                        }
                        @Override public void onConfigureFailed(CameraCaptureSession session) {
                            sessionLatch.countDown();
                            latch.countDown();
                        }
                    }, bg);
            sessionLatch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS);
            latch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS);
            try { device.close(); } catch (Exception ignored) {}
            reader.close();
        } catch (Exception e) {
            Log.w(TAG, "captureJpeg failed", e);
        } finally {
            thread.quitSafely();
        }
        lastJpeg = out[0];
        return lastJpeg;
    }

    public int getLastWidth() { return lastW; }
    public int getLastHeight() { return lastH; }

    private String chooseCameraId(CameraManager cm) throws CameraAccessException {
        String[] ids = cm.getCameraIdList();
        if (ids.length == 0) return null;
        String fallback = ids[0];
        String front = null;
        for (String id : ids) {
            CameraCharacteristics c = cm.getCameraCharacteristics(id);
            Integer facing = c.get(CameraCharacteristics.LENS_FACING);
            if (facing != null && facing == CameraCharacteristics.LENS_FACING_BACK) {
                return id; // outward-facing: the passthrough RGB cameras on Quest
            }
            if (facing != null && facing == CameraCharacteristics.LENS_FACING_FRONT) {
                front = id;
            }
        }
        return front != null ? front : fallback;
    }
}
