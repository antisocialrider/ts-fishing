document.addEventListener('DOMContentLoaded', () => {
    const notificationContainer = document.getElementById('notification-container');
    const notificationMessage = document.getElementById('notification-message');
    const minigameContainer = document.getElementById('minigame-container');
    const minigameKey = document.getElementById('minigame-key');

    let notificationTimeout = null;
    let minigameData = {}; // Stores minigame timing and key from Lua
    let highlightLoopInterval = null; // To manage the NUI-side highlighting loop

    function post(eventName, data) {
        // console.log(`NUI: Attempting to post to ${eventName} with data:`, data); // Keep this for debugging NUI -> Lua communication
        fetch(`https://${GetParentResourceName()}/${eventName}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8',
            },
            body: JSON.stringify(data),
        }).then(resp => {
            if (!resp.ok) {
                console.error(`NUI: Fetch error for ${eventName}: ${resp.status} ${resp.statusText}`);
            }
            return resp.json();
        }).then(resp => {
            // console.log(`NUI: Post to ${eventName} successful:`, resp); // Keep this for debugging
        }).catch(error => console.error(`NUI: Error during fetch for ${eventName}:`, error));
    }

    function showNotification(message, type) {
        if (notificationTimeout) {
            clearTimeout(notificationTimeout);
            notificationContainer.classList.remove('notification-fade-in', 'notification-fade-out');
            notificationContainer.style.opacity = '0';
            notificationContainer.style.display = 'none';
            void notificationContainer.offsetWidth;
        }

        notificationMessage.textContent = message;

        notificationContainer.classList.remove('notification-success', 'notification-info', 'notification-warning', 'notification-error');

        switch (type) {
            case 'success':
                notificationContainer.classList.add('notification-success');
                break;
            case 'info':
                notificationContainer.classList.add('notification-info');
                break;
            case 'warning':
                notificationContainer.classList.add('notification-warning');
                break;
            case 'error':
                notificationContainer.classList.add('notification-error');
                break;
            default:
                notificationContainer.classList.add('notification-info');
                break;
        }

        notificationContainer.style.display = 'block';
        notificationContainer.classList.add('notification-fade-in');
        notificationContainer.style.opacity = '1';

        notificationTimeout = setTimeout(() => {
            notificationContainer.classList.remove('notification-fade-in');
            notificationContainer.classList.add('notification-fade-out');
            notificationContainer.style.opacity = '0';
            setTimeout(() => {
                notificationContainer.style.display = 'none';
            }, 500);
        }, 3000);
    }

    function showMinigamePrompt(data) {
        minigameKey.textContent = data.key;
        minigameContainer.style.display = 'flex';
        minigameContainer.style.opacity = '1';

        // Store minigame data received from Lua, and the NUI's current time for reference
        minigameData = {
            key: data.key,
            minigameStartTime: data.minigameStartTime,
            minigameDuration: data.minigameDuration,
            targetWindowStart: data.targetWindowStart,
            targetWindowEnd: data.targetWindowEnd,
            nuiShowTime: performance.now() // Record NUI's high-resolution timestamp when minigame is shown
        };

        // Start a loop in JS to handle highlighting
        startMinigameHighlightLoop();
    }

    function hideMinigamePrompt() {
        minigameContainer.style.opacity = '0';
        minigameKey.classList.remove('highlight'); // Ensure highlight is removed
        setTimeout(() => {
            minigameContainer.style.display = 'none';
        }, 300);
        stopMinigameHighlightLoop(); // Stop the highlight loop when minigame hides
    }

    function startMinigameHighlightLoop() {
        if (highlightLoopInterval) clearInterval(highlightLoopInterval); // Clear any existing loop
        highlightLoopInterval = setInterval(() => {
            // Calculate current time relative to the minigame's start time in Lua's scale
            const elapsedNuiTime = performance.now() - minigameData.nuiShowTime;
            const currentMinigameTime = minigameData.minigameStartTime + elapsedNuiTime;

            const inWindow = (currentMinigameTime >= minigameData.targetWindowStart && currentMinigameTime <= minigameData.targetWindowEnd);
            
            if (inWindow) {
                minigameKey.classList.add('highlight');
            } else {
                minigameKey.classList.remove('highlight');
            }

            // If minigame duration passed, stop highlighting
            if (elapsedNuiTime > minigameData.minigameDuration) {
                stopMinigameHighlightLoop();
                minigameKey.classList.remove('highlight');
                // Optionally, send a 'failed' message to Lua if no key was pressed yet
                // This would require a flag to ensure it's only sent once if no success occurred.
            }
        }, 10); // Check every 10ms for smooth highlighting
    }

    function stopMinigameHighlightLoop() {
        if (highlightLoopInterval) {
            clearInterval(highlightLoopInterval);
            highlightLoopInterval = null;
        }
    }

    window.addEventListener('message', (event) => {
        const data = event.data;
        if (data.type === 'showNotification') {
            showNotification(data.message, data.notificationType);
        } else if (data.type === 'showMinigame') {
            showMinigamePrompt(data); // Pass the entire data object
        } else if (data.type === 'hideMinigame') {
            hideMinigamePrompt();
        }
        // The 'highlightMinigameKey' message is no longer needed as NUI handles highlighting
    });

    document.addEventListener('keydown', (event) => {
        if (minigameContainer.style.display === 'flex' && minigameData.key) {
            const targetKey = minigameData.key; // Use minigameData.key directly
            if (event.key.toUpperCase() === targetKey.toUpperCase()) {
                // Calculate current time relative to the minigame's start time in Lua's scale
                const currentTime = performance.now();
                const currentMinigameTime = minigameData.minigameStartTime + (currentTime - minigameData.nuiShowTime);

                const inWindow = (currentMinigameTime >= minigameData.targetWindowStart && currentMinigameTime <= minigameData.targetWindowEnd);
                
                console.log(`NUI: Key ${event.key.toUpperCase()} pressed. Current Minigame Time: ${currentMinigameTime}, Window: [${minigameData.targetWindowStart}, ${minigameData.targetWindowEnd}], In Window: ${inWindow}`);

                // Send the result back to Lua using a unique event name
                // The event.timeStamp is crucial for creating a unique callback ID in Lua
                post(`minigame_result_${minigameData.minigameStartTime}`, { success: inWindow });
                
                // Stop the highlight loop immediately after key press
                stopMinigameHighlightLoop();
                minigameKey.classList.remove('highlight'); // Remove highlight immediately

                event.preventDefault(); // Prevent default action (e.g., opening chat, moving character)
            }
        }
    });
});