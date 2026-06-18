document.addEventListener("DOMContentLoaded", () => {
  if (window.lucide) {
    window.lucide.createIcons();
  }

  const menuButton = document.querySelector(".mobile-menu-button");
  const mobileNav = document.querySelector(".mobile-nav");

  if (menuButton && mobileNav) {
    menuButton.addEventListener("click", () => {
      const isOpen = mobileNav.classList.toggle("open");
      menuButton.setAttribute("aria-expanded", String(isOpen));
    });

    mobileNav.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => {
        mobileNav.classList.remove("open");
        menuButton.setAttribute("aria-expanded", "false");
      });
    });
  }

  const approvalForm = document.querySelector("#beta-approval-form");
  if (!approvalForm) return;

  const emailInput = document.querySelector("#beta-emails");
  const subjectInput = document.querySelector("#approval-subject");
  const bodyInput = document.querySelector("#approval-body");
  const emailCount = document.querySelector("#email-count");
  const status = document.querySelector("#approval-status");
  const clearButton = document.querySelector("#clear-approval-form");
  const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  const parseEmails = () => {
    const entries = emailInput.value.split(/[\s,;]+/).map((value) => value.trim()).filter(Boolean);
    const uniqueEntries = [...new Set(entries.map((value) => value.toLowerCase()))];

    return {
      valid: uniqueEntries.filter((value) => emailPattern.test(value)),
      invalid: uniqueEntries.filter((value) => !emailPattern.test(value)),
    };
  };

  const updateCount = () => {
    const { valid, invalid } = parseEmails();
    emailCount.textContent = `${valid.length} valid${invalid.length ? `, ${invalid.length} invalid` : ""}`;
    status.textContent = "";
    status.className = "approval-status";
  };

  emailInput.addEventListener("input", updateCount);

  clearButton.addEventListener("click", () => {
    emailInput.value = "";
    updateCount();
    emailInput.focus();
  });

  approvalForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const { valid, invalid } = parseEmails();

    if (!valid.length || invalid.length) {
      status.textContent = invalid.length
        ? `Fix or remove ${invalid.length} invalid email address${invalid.length === 1 ? "" : "es"}.`
        : "Add at least one valid email address.";
      status.className = "approval-status approval-status-error";
      return;
    }

    if (!subjectInput.value.trim() || !bodyInput.value.trim()) {
      status.textContent = "Add both a subject and message before opening the email.";
      status.className = "approval-status approval-status-error";
      return;
    }

    const bcc = encodeURIComponent(valid.join(","));
    const subject = encodeURIComponent(subjectInput.value.trim());
    const body = encodeURIComponent(bodyInput.value.trim());
    const mailtoUrl = `mailto:support@aurumstack.app?bcc=${bcc}&subject=${subject}&body=${body}`;

    if (mailtoUrl.length > 1800) {
      status.textContent = "This recipient list is too large for a reliable email link. Split it into smaller batches and try again.";
      status.className = "approval-status approval-status-error";
      return;
    }

    status.textContent = `Opening an email with ${valid.length} recipient${valid.length === 1 ? "" : "s"} in BCC.`;
    status.className = "approval-status approval-status-success";
    window.location.href = mailtoUrl;
  });
});
