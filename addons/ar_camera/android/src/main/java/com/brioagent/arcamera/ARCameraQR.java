package com.brioagent.arcamera;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Log;

import com.google.zxing.BinaryBitmap;
import com.google.zxing.LuminanceSource;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.RGBLuminanceSource;
import com.google.zxing.Result;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.qrcode.QRCodeReader;

/**
 * QR / barcode decoding via ZXing core (pure Java, bundled into the AAR —
 * no Play Services, which don't exist on Quest).
 * Returns the decoded text, or "" when nothing is found.
 */
public class ARCameraQR {
    private static final String TAG = "ARCamera";

    public static String decode(byte[] jpeg) {
        if (jpeg == null || jpeg.length == 0) return "";
        try {
            Bitmap bmp = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.length);
            if (bmp == null) return "";
            int w = bmp.getWidth();
            int h = bmp.getHeight();
            int[] px = new int[w * h];
            bmp.getPixels(px, 0, w, 0, 0, w, h);
            LuminanceSource src = new RGBLuminanceSource(w, h, px);
            BinaryBitmap bb = new BinaryBitmap(new HybridBinarizer(src));
            try {
                Result r = new QRCodeReader().decode(bb);
                return r.getText();
            } catch (Exception qrFail) {
                try {
                    Result r = new MultiFormatReader().decode(bb);
                    return r.getText();
                } catch (Exception anyFail) {
                    return "";
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "QR decode failed", e);
            return "";
        }
    }
}
