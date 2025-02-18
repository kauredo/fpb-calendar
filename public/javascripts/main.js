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
        if (cachedTeams) {
          this.teams = JSON.parse(cachedTeams);
          this.filteredTeams = this.teams;
          document.getElementById("loading-screen").style.display = "none";
          return;
        }

        const response = await fetch("/api/teams");
        this.teams = await response.json();
        localStorage.setItem("teams", JSON.stringify(this.teams)); // Cache data
        this.filteredTeams = this.teams;
        document.getElementById("loading-screen").style.display = "none";
        // console.log("Teams loaded:", this.teams.length);
        // console.log("Sample team:", this.teams[0]);
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

      // console.log("Filtered teams:", this.filteredTeams.length);
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
      document.getElementById("team_url").value = team.url;
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
