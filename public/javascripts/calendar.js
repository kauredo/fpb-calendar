// Show the loading screen when the form is submitted
document.addEventListener("DOMContentLoaded", function () {
  // if page is not root, hide loading screen
  if (window.location.pathname !== "/") {
    document.getElementById("loading-screen").style.display = "none";
  }

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

document.addEventListener("DOMContentLoaded", () => {
  const calendar = {
    currentMonth: new Date(),
    games: [],

    init() {
      this.loadGames();
    },

    async loadGames() {
      const response = await fetch(`/api/teams/${params.id}`);
      const data = await response.json();
      this.games = data.games;
      this.renderCalendar();
    },

    renderCalendar() {
      const calendarDays = document.getElementById("calendar-days");
      calendarDays.innerHTML = "";

      const firstDay = new Date(
        this.currentMonth.getFullYear(),
        this.currentMonth.getMonth(),
        1
      );
      const lastDay = new Date(
        this.currentMonth.getFullYear(),
        this.currentMonth.getMonth() + 1,
        0
      );

      // Add empty days for the start of the month
      for (let i = 0; i < firstDay.getDay(); i++) {
        calendarDays.appendChild(this.createDayElement(""));
      }

      // Add days with games
      for (let date = 1; date <= lastDay.getDate(); date++) {
        const dayGames = this.games.filter(game => {
          const gameDate = new Date(game.date);
          return (
            gameDate.getDate() === date &&
            gameDate.getMonth() === this.currentMonth.getMonth() &&
            gameDate.getFullYear() === this.currentMonth.getFullYear()
          );
        });

        calendarDays.appendChild(this.createDayElement(date, dayGames));
      }

      this.updateMonthDisplay();
    },

    createDayElement(date, games = []) {
      const dayElement = document.createElement("div");
      dayElement.className = `calendar-day ${games.length ? "has-game" : ""}`;

      if (date) {
        dayElement.textContent = date;

        if (games.length) {
          const gameList = document.createElement("div");
          gameList.className = "game-list";
          gameList.style.position = "absolute";
          gameList.style.bottom = "20px";
          gameList.style.left = "5px";
          gameList.style.right = "5px";
          gameList.style.fontSize = "0.8em";
          gameList.style.color = "#666";

          games.forEach(game => {
            const gameElement = document.createElement("div");
            gameElement.textContent = `${game.name} vs ${game.teams}`;
            gameList.appendChild(gameElement);
          });

          dayElement.appendChild(gameList);
        }
      }

      return dayElement;
    },

    updateMonthDisplay() {
      const monthNames = [
        "Janeiro",
        "Fevereiro",
        "Março",
        "Abril",
        "Maio",
        "Junho",
        "Julho",
        "Agosto",
        "Setembro",
        "Outubro",
        "Novembro",
        "Dezembro",
      ];
      document.getElementById("current-month").textContent = `${
        monthNames[this.currentMonth.getMonth()]
      } ${this.currentMonth.getFullYear()}`;
    },
  };

  // Initialize the calendar when the page loads
  calendar.init();
});
