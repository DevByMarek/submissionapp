// TOTO JE DRAG AND DROP FUNKCIA
document.addEventListener("DOMContentLoaded", () => {
  const drop = document.querySelector(".file-drop-inner");
  const input = document.querySelector("#file");
  const fileName = document.querySelector(".file-name");

  if (!drop || !input || !fileName) return;

  drop.addEventListener("dragover", (e) => {
    e.preventDefault();
    drop.classList.add("dragover");
  });

  drop.addEventListener("dragleave", () => {
    drop.classList.remove("dragover");
  });

  drop.addEventListener("drop", (e) => {
    e.preventDefault();
    drop.classList.remove("dragover");

    input.files = e.dataTransfer.files;
    fileName.textContent = e.dataTransfer.files[0].name;
  });

  input.addEventListener("change", () => {
    fileName.textContent = input.files[0]?.name || "";
  });
});
