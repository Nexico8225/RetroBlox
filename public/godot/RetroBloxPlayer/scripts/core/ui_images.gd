extends RefCounted
class_name UiImages
## ==================================================================
##  UIIMAGES — textures for IMAGE widgets (v6.0 "UI STUDIO")
## ==================================================================
##  An "image" widget stores a URL; this loader downloads it once,
##  caches it for the session, and fills every TextureRect that asks.
##  PNG + JPG only (the classic web), 8s timeout, safe failures: the
##  widget keeps its placeholder instead of erroring the HUD.

static var _cache: Dictionary = {}   # url -> ImageTexture


## Kick an async download; when it lands the rect gets the texture.
static func load_into(rect: TextureRect, url: String) -> void:
        if url == "" or rect == null or not is_instance_valid(rect):
                return
        if _cache.has(url):
                rect.texture = _cache[url]
                return
        # one loader per request, parented to the rect so it dies with it
        var http := HTTPRequest.new()
        http.timeout = 8.0
        http.use_threads = true
        rect.add_child(http)
        var got: Array = await http.request_completed
        http.queue_free()
        if not is_instance_valid(rect) or got.is_empty():
                return
        var status: int = got[1]
        var body: PackedByteArray = got[3]
        if status != 200 or body.is_empty():
                return
        var img := Image.new()
        var head := body.slice(0, 4)
        var err := ERR_FILE_UNRECOGNIZED
        if head.size() >= 3 and head[0] == 0xFF and head[1] == 0xD8:
                err = img.load_jpg_from_buffer(body)
        else:
                err = img.load_png_from_buffer(body)
        if err != OK or img.is_empty():
                return
        var tex := ImageTexture.create_from_image(img)
        _cache[url] = tex
        if is_instance_valid(rect):
                rect.texture = tex
