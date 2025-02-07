// Show the loading screen when the form is submitted
document.addEventListener("DOMContentLoaded", function () {
  document.getElementById("loading-screen").style.display = "none";

  const form = document.getElementById("invite-form");
  if (form) {
    form.addEventListener("submit", function () {
      document.getElementById("loading-screen").style.display = "flex";
    });
  }

  document
    .querySelector(".dropdown-toggle")
    .addEventListener("click", function () {
      var dropdown = this.parentElement;
      dropdown.classList.toggle("open");
    });
});
