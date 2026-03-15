(function() {
  "use strict";

  function setInputValue(input, value) {
    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value");
    if (setter && setter.set) {
      setter.set.call(input, value);
    } else {
      input.value = value;
    }
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function cleanupUrl() {
    var url = new URL(window.location.href);
    var changed = false;

    ["pveDcvUser", "pveDcvPassword", "pveDcvAutoSubmit"].forEach(function(key) {
      if (!url.searchParams.has(key)) return;
      url.searchParams.delete(key);
      changed = true;
    });

    if (changed) {
      window.history.replaceState({}, document.title, url.toString());
    }
  }

  function findLoginButton() {
    return Array.from(document.querySelectorAll("button, input[type='submit'], [role='button']")).find(function(node) {
      return /sign in|login|anmelden/i.test(String(node.textContent || node.value || ""));
    });
  }

  function run() {
    var url = new URL(window.location.href);
    var username = url.searchParams.get("pveDcvUser") || "";
    var password = url.searchParams.get("pveDcvPassword") || "";
    var autoSubmit = url.searchParams.get("pveDcvAutoSubmit") !== "0";

    if (!username && !password) return;

    cleanupUrl();

    var attempts = 0;
    var timer = window.setInterval(function() {
      var inputs = Array.from(document.querySelectorAll("input"));
      var userInput = inputs.find(function(input) {
        return /user/i.test(String(input.name || input.id || input.placeholder || ""));
      }) || inputs.find(function(input) {
        return input.type === "text" || input.type === "email" || !input.type;
      });
      var passwordInput = inputs.find(function(input) {
        return input.type === "password";
      });

      attempts += 1;

      if (userInput && username && userInput.value !== username) {
        setInputValue(userInput, username);
      }

      if (passwordInput && password && passwordInput.value !== password) {
        setInputValue(passwordInput, password);
      }

      if (autoSubmit && userInput && passwordInput) {
        var button = findLoginButton();
        if (button) {
          button.click();
          window.clearInterval(timer);
          return;
        }
      }

      if (attempts >= 60) {
        window.clearInterval(timer);
      }
    }, 500);
  }

  run();
})();
