// Add the calendar to the team page
document.addEventListener("DOMContentLoaded", function () {
  const loadingScreen = document.getElementById("loading-screen");
  const teamId = window.location.pathname.split("/").pop();

  fetch(`/api/teams/${teamId}`)
    .then(response => response.json())
    .then(data => {
      // Get current date
      const today = new Date();
      const currentMonth = today.getMonth();
      const currentYear = today.getFullYear();

      const calendar = new VanillaCalendar("#calendar", {
        settings: {
          lang: "pt-PT",
          selection: {
            day: "single",
          },
          selected: {
            dates: [],
            month: currentMonth,
            year: currentYear,
          },
          visibility: {
            theme: "light",
            weekend: true,
            today: true,
            disabled: false,
          },
        },
        actions: {
          clickDay(e, dates) {
            const clickedDate = dates[0];
            const gamesOnDay = data.games.filter(
              game => game.date === clickedDate
            );
            updateMarks(calendar, data.games, clickedDate);
            setTimeout(() => {
              updateMarks(calendar, data.games, clickedDate);
            }, 0);
            if (gamesOnDay.length > 0) {
              const popupContent = document.createElement("div");
              popupContent.className = "games-popup";

              gamesOnDay.forEach(game => {
                const gameEl = document.createElement("div");
                gameEl.className = "game-details";

                const gameTitle = document.createElement("h3");
                gameTitle.textContent = game.teams;

                const gameInfo = document.createElement("div");

                const [homeTeam, awayTeam] = game.teams.split(" vs ");
                const isHomeTeam = homeTeam === game.name;

                let teamScore = null;
                let opponentScore = null;
                let didWin = null;

                if (game.result) {
                  const [score1, score2] = game.result.split("-").map(Number);
                  teamScore = isHomeTeam ? score1 : score2;
                  opponentScore = isHomeTeam ? score2 : score1;
                  didWin = teamScore > opponentScore;
                }

                gameInfo.innerHTML = `
                  <p class="competition">${game.competition}</p>
                  <p class="location">${game.location}</p>
                  ${
                    game.time &&
                    game.time.length > 0 &&
                    game.time != null &&
                    `<p class="time">Hora: ${game.time}</p>`
                  }
                  ${
                    game.result &&
                    game.result.length > 0 &&
                    game.result != null &&
                    `<p class="result ${
                      didWin ? "result--win" : "result--loss"
                    }">${didWin ? "Vitória" : "Derrota"}: ${game.result}</p>`
                  }
                  ${
                    game.link
                      ? `<a href="${game.link}" target="_blank" rel="noopener noreferrer">Ver detalhes →</a>`
                      : ""
                  }
                `;

                gameEl.appendChild(gameTitle);
                gameEl.appendChild(gameInfo);
                gameEl.dataset.game = JSON.stringify(game);
                popupContent.appendChild(gameEl);
              });

              // Remove any existing popup
              const existingPopup = document.querySelector(".games-popup");
              if (existingPopup) {
                existingPopup.remove();
              }

              // Create overlay and modal logic
              const overlay = document.createElement("div");
              overlay.classList.add("games-overlay");
              document.body.appendChild(overlay);

              popupContent.classList.add("modal-popup");
              overlay.classList.add("active");
              popupContent.classList.add("active");

              overlay.addEventListener("click", () => {
                overlay.remove();
                popupContent.remove();
              });

              document.body.appendChild(popupContent);

              // Close popup when clicking outside
              const closePopup = e => {
                if (
                  !popupContent.contains(e.target) &&
                  !e.target.classList.contains("games-overlay")
                ) {
                  popupContent.remove();
                  overlay.remove();
                  document.removeEventListener("click", closePopup);
                }
                updateMarks(calendar, data.games);
              };

              // Delay adding the event listener to prevent immediate closure
              setTimeout(() => {
                document.addEventListener("click", closePopup);
              }, 0);
            }
          },
          clickArrow(e) {
            updateMarks(calendar, data.games);
          },
          clickMonth(e) {
            setTimeout(() => {
              updateMarks(calendar, data.games);
            }, 0);
          },
          clickYear(e) {
            setTimeout(() => {
              updateMarks(calendar, data.games);
            }, 0);
          },
        },
      });

      function updateMarks(calendar, games, clickedDate = "") {
        // Get all date elements
        const dateElements = calendar.HTMLElement.querySelectorAll(
          ".vanilla-calendar-day__btn"
        );

        // Remove existing marks
        dateElements.forEach(dateEl => {
          dateEl.classList.remove("has-game", "has-multiple-games");
          dateEl.removeAttribute("data-game-count");
        });

        // Add new marks
        dateElements.forEach(dateEl => {
          const date = dateEl.dataset.calendarDay;
          const gamesOnDay = games.filter(game => game.date === date);

          if (gamesOnDay.length > 0 && clickedDate !== date) {
            dateEl.classList.add("has-game");
            dateEl.setAttribute("data-game-count", gamesOnDay.length);

            if (gamesOnDay.length > 1) {
              dateEl.classList.add("has-multiple-games");
            }
          }
        });
      }

      calendar.init();

      // Initial marking of dates with games
      updateMarks(calendar, data.games);
      loadingScreen.style.display = "none";
    })
    .catch(error => {
      console.error("Error fetching calendar data:", error);
      loadingScreen.style.display = "none";
    });
});
