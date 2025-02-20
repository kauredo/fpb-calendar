// Show the loading screen when the form is submitted
document.addEventListener("DOMContentLoaded", function () {
  const form = document.getElementById("invite-form");
  if (form) {
    form.addEventListener("submit", function () {
      document.getElementById("loading-screen").style.display = "flex";
    });
  }

  const teamUrl = document.getElementById("team_url");
  if (teamUrl) {
    if (teamUrl.value !== "") {
      teamUrl.style.cursor = "pointer";
      teamUrl.addEventListener("click", function () {
        const newWindow = window.open(this.value, "_blank");
        newWindow.opener = null;
        newWindow.focus();
      });
    } else {
      teamUrl.style.cursor = "not-allowed";
    }
  }

  document
    .querySelector(".dropdown-toggle")
    .addEventListener("click", function () {
      var dropdown = this.parentElement;
      dropdown.classList.toggle("open");
    });

  if (document.getElementById("team_url").value === "") {
    btn = document.getElementById("calendar-button");
    btn.disabled = true;
  } else {
    btn = document.getElementById("calendar-button");
    btn.disabled = false;
    const teamId = document
      .getElementById("team_url")
      .value.split("/")
      .pop()
      .split("_")
      .pop();
    btn.onclick = function (e) {
      e.preventDefault();
      window.location.href = "/calendar/" + teamId;
    };
  }
});

// Register Alpine component
document.addEventListener("alpine:init", () => {
  // document.getElementById("loading-screen").style.display = "flex";
  Alpine.data("teamSelector", () => ({
    teams: [],
    filters: {
      name: "",
      age: "",
      gender: "",
    },
    filteredTeams: [],
    selectedTeam: null,
    debounceTimeout: null,

    async init() {
      try {
        const cachedTeams = localStorage.getItem("teams");
        if (cachedTeams && cachedTeams.length > 0 && cachedTeams !== "[]") {
          this.teams = JSON.parse(cachedTeams);
          this.filteredTeams = this.teams;
          document.getElementById("loading-screen").style.display = "none";
          return;
        }

        const teamsResponse = await fetch("/api/teams");
        let teams = await teamsResponse.json();

        // If there are no teams, refresh the data
        if (teams.length === 0) {
          const fullResponse = await fetch("/api/refresh");
          const data = await fullResponse.json();
          teams = data.teams;
        }

        this.teams = teams;
        localStorage.setItem("teams", JSON.stringify(this.teams)); // Cache data
        this.filteredTeams = this.teams;
        document.getElementById("loading-screen").style.display = "none";
      } catch (error) {
        console.error("Error loading teams:", error);
      }
    },

    updateFilters() {
      this.filteredTeams = this.teams.filter(team => {
        return Object.entries(this.filters).every(([key, value]) => {
          if (!value) return true;
          return (
            team[key] &&
            team[key].toString().toLowerCase().includes(value.toLowerCase())
          );
        });
      });
    },

    debounceUpdateFilters() {
      // Clear any existing timeout
      if (this.debounceTimeout) {
        clearTimeout(this.debounceTimeout);
      }

      // Set a new timeout
      this.debounceTimeout = setTimeout(() => {
        this.updateFilters();
      }, 300); // 300ms debounce delay
    },

    getUniqueValues(field) {
      if (!this.teams || this.teams.length === 0) return [];
      const values = [...new Set(this.teams.map(team => team[field]))].filter(
        value => value
      );
      return values.sort();
    },

    selectTeam(team) {
      this.selectedTeam = team;
      const teamUrl = document.getElementById("team_url");
      teamUrl.value = team.url;
      teamUrl.style.cursor = "pointer";
      teamUrl.addEventListener("click", function () {
        const newWindow = window.open(team.url, "_blank");
        newWindow.opener = null;
        newWindow.focus();
      });
      // make button not disabled and redirect to /calendar/id
      btn = document.getElementById("calendar-button");
      btn.disabled = false;
      btn.onclick = function (e) {
        e.preventDefault();
        window.location.href = "/calendar/" + team.id;
      };
    },
  }));
});
