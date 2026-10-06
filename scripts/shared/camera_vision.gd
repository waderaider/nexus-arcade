## CameraVision.gd - on-device computer-vision helpers for NEXUS ARCADE.
## Pure GDScript, no ML API, no key, no network. Works on any Image
## (camera captures via ARCamera, or synthetic test images on desktop).
## All helpers downscale internally so they stay fast on-device.
## Headless-safe: pure math on Image data, no rendering or XR needed.
extends RefCounted
class_name CameraVision

## Named color buckets used by analyze_colors().
const COLOR_NAMES := [
	"red", "orange", "yellow", "green", "cyan",
	"blue", "purple", "pink", "brown", "white", "gray", "black",
]


## Downscale helper (never upscales).
static func _small(img: Image, max_side: int = 64) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return img
	var scale := float(max_side) / float(maxi(w, h))
	if scale >= 1.0:
		return img
	var c := img.duplicate()
	c.resize(int(w * scale), int(h * scale), Image.INTERPOLATE_BILINEAR)
	return c


## Classify one pixel into a named bucket.
static func classify_pixel(c: Color) -> String:
	var mx := maxf(maxf(c.r, c.g), c.b)
	var mn := minf(minf(c.r, c.g), c.b)
	var sat := mx - mn
	var v := mx
	if v < 0.12:
		return "black"
	if sat < 0.10:
		return "white" if v > 0.75 else ("gray" if v > 0.35 else "black")
	var hue := 0.0
	if sat > 0.0001:
		if mx == c.r:
			hue = fposmod((c.g - c.b) / sat, 6.0) * 60.0
		elif mx == c.g:
			hue = ((c.b - c.r) / sat + 2.0) * 60.0
		else:
			hue = ((c.r - c.g) / sat + 4.0) * 60.0
	# Low-saturation warm tones read as brown.
	if sat < 0.45 and v < 0.55 and hue < 60.0:
		return "brown"
	if hue < 15.0 or hue >= 345.0:
		return "red"
	if hue < 45.0:
		return "orange"
	if hue < 75.0:
		return "yellow"
	if hue < 150.0:
		return "green"
	if hue < 195.0:
		return "cyan"
	if hue < 255.0:
		return "blue"
	if hue < 300.0:
		return "purple"
	return "pink"


## Fraction of pixels in each named bucket. {name: 0.0-1.0}.
static func analyze_colors(img: Image) -> Dictionary:
	var result := {}
	for n in COLOR_NAMES:
		result[n] = 0.0
	if img == null or img.is_empty():
		return result
	var s := _small(img)
	var w := s.get_width()
	var h := s.get_height()
	var total := 0
	for y in h:
		for x in w:
			result[classify_pixel(s.get_pixel(x, y))] += 1.0
			total += 1
	if total > 0:
		for n in COLOR_NAMES:
			result[n] = float(result[n]) / float(total)
	return result


## Name of the most common color bucket.
static func dominant_color_name(img: Image) -> String:
	var hist := analyze_colors(img)
	var best := "gray"
	var best_v := -1.0
	for n in COLOR_NAMES:
		if float(hist[n]) > best_v:
			best_v = float(hist[n])
			best = n
	return best


## Fraction of pixels within `tol` (0-1) of `target` in RGB. For Eye Spy.
static func color_match_fraction(img: Image, target: Color, tol: float = 0.18) -> float:
	if img == null or img.is_empty():
		return 0.0
	var s := _small(img)
	var w := s.get_width()
	var h := s.get_height()
	var hit := 0
	var total := 0
	for y in h:
		for x in w:
			var c := s.get_pixel(x, y)
			var d := absf(c.r - target.r) + absf(c.g - target.g) + absf(c.b - target.b)
			if d <= tol * 3.0:
				hit += 1
			total += 1
	return float(hit) / float(maxi(total, 1))


## Mean brightness 0.0-1.0.
static func brightness(img: Image) -> float:
	if img == null or img.is_empty():
		return 0.0
	var s := _small(img, 32)
	var w := s.get_width()
	var h := s.get_height()
	var sum := 0.0
	var total := 0
	for y in h:
		for x in w:
			var c := s.get_pixel(x, y)
			sum += 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			total += 1
	return sum / float(maxi(total, 1))


## Sobel edge map on a downscaled grayscale copy. Bright = edge.
static func sobel_edges(img: Image, target_w: int = 64) -> Image:
	var out := Image.create(1, 1, false, Image.FORMAT_L8)
	if img == null or img.is_empty():
		return out
	var s := _small(img, target_w)
	var w := s.get_width()
	var h := s.get_height()
	out = Image.create(w, h, false, Image.FORMAT_L8)
	var gray := PackedFloat32Array()
	gray.resize(w * h)
	for y in h:
		for x in w:
			var c := s.get_pixel(x, y)
			gray[y * w + x] = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var gx := (
				-gray[(y - 1) * w + x - 1] - 2.0 * gray[y * w + x - 1] - gray[(y + 1) * w + x - 1]
				+ gray[(y - 1) * w + x + 1] + 2.0 * gray[y * w + x + 1] + gray[(y + 1) * w + x + 1]
			)
			var gy := (
				-gray[(y - 1) * w + x - 1] - 2.0 * gray[(y - 1) * w + x] - gray[(y - 1) * w + x + 1]
				+ gray[(y + 1) * w + x - 1] + 2.0 * gray[(y + 1) * w + x] + gray[(y + 1) * w + x + 1]
			)
			var m := clampf(sqrt(gx * gx + gy * gy) / 4.0, 0.0, 1.0)
			out.set_pixel(x, y, Color(m, m, m))
	return out


## Fraction of edge pixels above threshold. High = busy/detailed scene.
static func edge_density(img: Image, threshold: float = 0.35) -> float:
	var e := sobel_edges(img)
	var w := e.get_width()
	var h := e.get_height()
	if w <= 2 or h <= 2:
		return 0.0
	var hit := 0
	var total := 0
	for y in h:
		for x in w:
			if e.get_pixel(x, y).r >= threshold:
				hit += 1
			total += 1
	return float(hit) / float(maxi(total, 1))


## Rough circularity 0.0-1.0 from edge-pixel radial variance.
## 1.0 = edge pixels all equidistant from centroid (circle-like).
static func roundness(img: Image) -> float:
	var e := sobel_edges(img, 48)
	var w := e.get_width()
	var h := e.get_height()
	var pts := PackedVector2Array()
	for y in h:
		for x in w:
			if e.get_pixel(x, y).r >= 0.4:
				pts.append(Vector2(x, y))
	if pts.size() < 24:
		return 0.0
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += p
	centroid /= float(pts.size())
	var mean := 0.0
	for p in pts:
		mean += centroid.distance_to(p)
	mean /= float(pts.size())
	if mean < 1.0:
		return 0.0
	var var_sum := 0.0
	for p in pts:
		var d := centroid.distance_to(p) - mean
		var_sum += d * d
	var std := sqrt(var_sum / float(pts.size()))
	return clampf(1.0 - (std / mean), 0.0, 1.0)
