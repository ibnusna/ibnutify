let timerInterval;

function startTimer(durationInMinutes, displayElement, onTimerEndCallback) {
  const now = Date.now();
  let examEndTime = sessionStorage.getItem("examEndTime");

  // Jika belum ada examEndTime, buat yang baru
  if (!examEndTime) {
    examEndTime = now + durationInMinutes * 60 * 1000;
    sessionStorage.setItem("examEndTime", examEndTime);
    console.log("Timer dimulai baru:", new Date(examEndTime).toLocaleString());
  } else {
    examEndTime = parseInt(examEndTime, 10);
    console.log("Timer melanjutkan dari:", new Date(examEndTime).toLocaleString());
  }

  // Hitung sisa waktu dalam detik
  let remainingTime = Math.floor((examEndTime - now) / 1000);

  // Jika waktu sudah habis, langsung panggil callback
  if (remainingTime <= 0) {
    if (displayElement) {
      displayElement.textContent = "00:00";
    }
    if (onTimerEndCallback && typeof onTimerEndCallback === "function") {
      onTimerEndCallback();
    }
    return;
  }

  const updateDisplay = () => {
    const minutes = Math.floor(remainingTime / 60);
    const seconds = remainingTime % 60;

    const displayMinutes = minutes < 10 ? "0" + minutes : minutes;
    const displaySeconds = seconds < 10 ? "0" + seconds : seconds;

    if (displayElement) {
      displayElement.textContent = displayMinutes + ":" + displaySeconds;
    }
  };

  updateDisplay();

  timerInterval = setInterval(() => {
    remainingTime--;

    if (remainingTime < 0) {
      clearInterval(timerInterval);
      sessionStorage.removeItem("examEndTime");
      
      if (onTimerEndCallback && typeof onTimerEndCallback === "function") {
        onTimerEndCallback();
      }
    } else {
      updateDisplay();
    }
  }, 1000);
}

function stopTimer() {
  if (timerInterval) {
    clearInterval(timerInterval);
    timerInterval = null;
  }
}