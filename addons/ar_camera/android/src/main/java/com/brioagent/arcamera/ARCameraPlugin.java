package com.brioagent.arcamera;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Arrays;
import java.util.List;

/**
 * Godot Android plugin "ARCamera" — Quest 3 passthrough camera access.
 * GDScript: var cam = Engine.get_singleton("ARCamera")
 *           cam.captureFrame() -> PackedByteArray (JPEG)
 */
public class ARCameraPlugin extends GodotPlugin {

    private final ARCameraCapture capture;

    public ARCameraPlugin(Godot godot) {
        super(godot);
        capture = new ARCameraCapture(godot.getContext());
    }

    @Override
    public String getPluginName() {
        return "ARCamera";
    }

    @Override
    public List<String> getPluginMethods() {
        return Arrays.asList(
                "isCameraAvailable",
                "requestCameraPermission",
                "captureFrame",
                "getFrameWidth",
                "getFrameHeight",
                "scanQR"
        );
    }

    @UsedByGodot
    public boolean isCameraAvailable() {
        return capture.isAvailable();
    }

    @UsedByGodot
    public void requestCameraPermission() {
        capture.requestPermission(getActivity());
    }

    /** JPEG bytes of a single still capture, or null. */
    @UsedByGodot
    public byte[] captureFrame() {
        return capture.captureJpeg();
    }

    @UsedByGodot
    public int getFrameWidth() {
        return capture.getLastWidth();
    }

    @UsedByGodot
    public int getFrameHeight() {
        return capture.getLastHeight();
    }

    /** Decodes a QR/barcode from a fresh capture. "" when none found. */
    @UsedByGodot
    public String scanQR() {
        return ARCameraQR.decode(capture.captureJpeg());
    }
}
