function createDreamSkinMediaLayer(environment = globalThis) {
  const document = environment.document;
  const mediaQuery = typeof environment.matchMedia === "function"
    ? environment.matchMedia("(prefers-reduced-motion: reduce)")
    : { matches: false, addEventListener() {}, removeEventListener() {} };

  function mount({ posterUrl, videoUrl }) {
    if (!document?.body || typeof posterUrl !== "string" || !posterUrl) {
      throw new Error("Dream Skin media layer requires a document body and poster URL");
    }

    const root = document.createElement("div");
    root.setAttribute("data-dream-media-layer", "true");
    Object.assign(root.style, {
      position: "fixed",
      inset: "0",
      zIndex: "-1",
      overflow: "hidden",
      pointerEvents: "none",
      backgroundImage: `url(${JSON.stringify(posterUrl)})`,
      backgroundPosition: "var(--dream-skin-art-position, center)",
      backgroundRepeat: "no-repeat",
      backgroundSize: "cover",
    });

    let video = null;
    let disposed = false;
    let failed = false;

    const shouldPlay = () => !disposed && !failed && !document.hidden && !mediaQuery.matches;
    const showPoster = () => {
      if (!video) return;
      video.pause();
      video.style.display = "none";
    };
    const playWhenAllowed = async () => {
      if (!video || !shouldPlay()) {
        showPoster();
        return;
      }
      video.style.display = "block";
      try {
        await video.play();
      } catch {
        failed = true;
        showPoster();
      }
    };
    const failToPoster = () => {
      failed = true;
      showPoster();
    };
    const handleVisibility = () => { void playWhenAllowed(); };
    const handleMotion = () => { void playWhenAllowed(); };

    if (typeof videoUrl === "string" && videoUrl) {
      video = document.createElement("video");
      video.src = videoUrl;
      video.muted = true;
      video.loop = true;
      video.autoplay = true;
      video.controls = false;
      video.playsInline = true;
      video.preload = "auto";
      video.setAttribute("aria-hidden", "true");
      video.setAttribute("tabindex", "-1");
      Object.assign(video.style, {
        width: "100%",
        height: "100%",
        objectFit: "cover",
        objectPosition: "var(--dream-skin-art-position, center)",
        pointerEvents: "none",
      });
      video.addEventListener("error", failToPoster);
      video.addEventListener("stalled", failToPoster);
      root.appendChild(video);
    }

    document.body.appendChild(root);
    document.addEventListener("visibilitychange", handleVisibility);
    mediaQuery.addEventListener?.("change", handleMotion);
    void playWhenAllowed();

    return {
      root,
      video,
      dispose() {
        if (disposed) return;
        disposed = true;
        document.removeEventListener("visibilitychange", handleVisibility);
        mediaQuery.removeEventListener?.("change", handleMotion);
        if (video) {
          video.removeEventListener("error", failToPoster);
          video.removeEventListener("stalled", failToPoster);
          video.pause();
          video.removeAttribute?.("src");
        }
        root.remove();
      },
    };
  }

  return Object.freeze({ mount });
}

if (typeof module === "object" && module?.exports) {
  module.exports = createDreamSkinMediaLayer;
}
