// Add a class early so CSS animations are only enabled when JavaScript is available.
document.documentElement.classList.add("js");

const revealItems = document.querySelectorAll(".reveal");

if ("IntersectionObserver" in window) {
  const revealObserver = new IntersectionObserver(
    (entries, observer) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12 }
  );

  revealItems.forEach((item) => revealObserver.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}

function initDeviceCarousel() {
  const carousel = document.querySelector("[data-device-carousel]");

  if (!carousel) {
    return;
  }

  const viewport = carousel.querySelector("[data-carousel-viewport]");
  const slides = Array.from(carousel.querySelectorAll("[data-carousel-slide]"));
  const dots = Array.from(carousel.querySelectorAll("[data-carousel-dot]"));

  if (!viewport || slides.length < 2) {
    return;
  }

  let activeIndex = 0;
  let pointerStartX = null;
  let suppressClick = false;

  function setActive(index) {
    activeIndex = (index + slides.length) % slides.length;

    slides.forEach((slide, slideIndex) => {
      const isActive = slideIndex === activeIndex;
      slide.classList.toggle("is-active", isActive);
      slide.classList.toggle("is-behind", !isActive);
    });

    dots.forEach((dot, dotIndex) => {
      dot.setAttribute("aria-selected", String(dotIndex === activeIndex));
    });
  }

  slides.forEach((slide) => {
    slide.addEventListener("click", () => {
      if (!suppressClick && slide.classList.contains("is-behind")) {
        setActive(Number(slide.dataset.carouselSlide));
      }
    });
  });

  dots.forEach((dot) => {
    dot.addEventListener("click", () => {
      setActive(Number(dot.dataset.carouselDot));
    });
  });

  viewport.addEventListener("pointerdown", (event) => {
    if (event.isPrimary) {
      pointerStartX = event.clientX;
    }
  });

  viewport.addEventListener("pointerup", (event) => {
    if (pointerStartX === null || !event.isPrimary) {
      return;
    }

    const distance = event.clientX - pointerStartX;
    pointerStartX = null;

    if (Math.abs(distance) > 40) {
      suppressClick = true;
      setActive(activeIndex + (distance < 0 ? 1 : -1));
      window.setTimeout(() => {
        suppressClick = false;
      }, 0);
    }
  });

  viewport.addEventListener("pointercancel", () => {
    pointerStartX = null;
  });

  viewport.addEventListener("keydown", (event) => {
    if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
      event.preventDefault();
      setActive(activeIndex + (event.key === "ArrowRight" ? 1 : -1));
    }
  });

  setActive(activeIndex);
}

document.addEventListener("DOMContentLoaded", initDeviceCarousel);
