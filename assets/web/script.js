const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    window.setTimeout(() => {
      document.getElementById('intro-splash').hidden = true;
      document.getElementById('splash-screen').hidden = false;
    }, prefersReducedMotion ? 1200 : 3200);

    document.addEventListener('click', (event) => {
      const button = event.target.closest('button:not(:disabled)');
      if (!button || prefersReducedMotion) return;
      const bounds = button.getBoundingClientRect();
      const diameter = Math.max(bounds.width, bounds.height) * 1.6;
      const ripple = document.createElement('span');
      ripple.className = 'ui-ripple';
      ripple.style.width = `${diameter}px`;
      ripple.style.height = `${diameter}px`;
      ripple.style.left = `${event.clientX - bounds.left - diameter / 2}px`;
      ripple.style.top = `${event.clientY - bounds.top - diameter / 2}px`;
      button.append(ripple);
      window.setTimeout(() => ripple.remove(), 600);
    });

    const rideList = document.getElementById('ride-list');
    let cards = [...rideList.querySelectorAll('.ride-card')];
    const toast = document.getElementById('toast');
    let toastTimer;
    const supabaseUrl = 'https://ecefjyoaqyxdjyjsmpyd.supabase.co';
    const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVjZWZqeW9hcXl4ZGp5anNtcHlkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE0MzEzMjksImV4cCI6MjEwNzAwNzMyOX0.OjXaQLer79sq6A-FK2_rX4-pA71ylESawGHabINxf28';
    const profileStorageKey = 'sharemyride-profile';
    let profileData = { name: 'Alex Morgan', email: '', phone: '' };
    try {
      profileData = { ...profileData, ...JSON.parse(localStorage.getItem(profileStorageKey) || '{}') };
    } catch (error) {
      // Continue with the default profile when browser storage is unavailable.
    }
    const bookings = [];
    let accessToken = null;
    let currentUserId = null;
    let pendingRideId = null;
    let pendingRideDetails = null;
    let razorpayCheckoutPromise = null;

    function updateProfileDisplay() {
      const initials = profileData.name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join('').toUpperCase() || 'AM';
      document.getElementById('profile-name').textContent = profileData.name;
      document.getElementById('profile-avatar').textContent = initials;
      document.getElementById('profile-button').setAttribute('aria-label', `Open profile menu for ${profileData.name}`);
      document.getElementById('menu-profile-name').textContent = profileData.name;
      document.getElementById('menu-profile-email').textContent = profileData.email || 'Add your email address';
      const offerPhone = document.getElementById('offer-phone');
      if (offerPhone && !offerPhone.value) offerPhone.value = profileData.phone;
      cards.filter((card) => card.dataset.owner === 'true').forEach((card) => {
        const driverName = card.querySelector('.ride-driver-name, .driver-name');
        const driverAvatar = card.querySelector('.ride-driver-avatar, .driver-avatar');
        if (driverName) driverName.textContent = profileData.name;
        if (driverAvatar) driverAvatar.textContent = initials;
      });
    }
    updateProfileDisplay();

    function showToast(message) {
      toast.textContent = message;
      toast.classList.add('show');
      clearTimeout(toastTimer);
      toastTimer = setTimeout(() => toast.classList.remove('show'), 2600);
    }

    async function supabaseRequest(path, options = {}) {
      if (!accessToken || !currentUserId) {
        throw new Error('Please log in again to access your rides.');
      }
      const headers = {
        apikey: supabaseAnonKey,
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        ...options.headers
      };
      const response = await fetch(`${supabaseUrl}/${path}`, { ...options, headers });
      const responseText = await response.text();
      let result = null;
      if (responseText) {
        try {
          result = JSON.parse(responseText);
        } catch (error) {
          throw new Error('The server returned an invalid response.');
        }
      }
      if (!response.ok) {
        throw new Error(result?.message || result?.hint || result?.details || 'Could not save or load ride data.');
      }
      return result;
    }

    async function ridePaymentRequest(payload) {
      if (!accessToken || !currentUserId) {
        throw new Error('Please log in before paying to publish a ride.');
      }
      const response = await fetch(`${supabaseUrl}/functions/v1/ride-payment`, {
        method: 'POST',
        headers: {
          apikey: supabaseAnonKey,
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });
      const result = await response.json().catch(() => null);
      if (!response.ok) {
        throw new Error(result?.message || 'Could not prepare or verify the ride payment.');
      }
      return result;
    }

    function loadRazorpayCheckout() {
      if (window.Razorpay) return Promise.resolve();
      if (razorpayCheckoutPromise) return razorpayCheckoutPromise;
      razorpayCheckoutPromise = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = 'https://checkout.razorpay.com/v1/checkout.js';
        script.async = true;
        script.onload = () => window.Razorpay
          ? resolve()
          : reject(new Error('Razorpay checkout did not load. Check your internet connection.'));
        script.onerror = () => reject(new Error('Could not load Razorpay checkout. Check your internet connection.'));
        document.head.append(script);
      }).catch((error) => {
        razorpayCheckoutPromise = null;
        throw error;
      });
      return razorpayCheckoutPromise;
    }

    function openRidePaymentCheckout(order, phone) {
      return new Promise((resolve, reject) => {
        let settled = false;
        const rejectOnce = (error) => {
          if (settled) return;
          settled = true;
          reject(error);
        };
        const checkout = new window.Razorpay({
          key: order.key_id,
          amount: order.amount,
          currency: order.currency,
          name: 'CoRiderly',
          description: 'One-time ride publishing fee',
          order_id: order.order_id,
          prefill: { contact: phone },
          theme: { color: '#7c3aed' },
          handler: async (payment) => {
            try {
              const result = await ridePaymentRequest({
                action: 'verify_payment',
                ride_id: order.ride_id,
                razorpay_order_id: payment.razorpay_order_id,
                razorpay_payment_id: payment.razorpay_payment_id,
                razorpay_signature: payment.razorpay_signature
              });
              if (!result?.ride) {
                throw new Error('Payment was verified, but the ride was not returned. Refresh your rides.');
              }
              if (settled) return;
              settled = true;
              resolve(result.ride);
            } catch (error) {
              rejectOnce(error);
            }
          },
          modal: {
            ondismiss: () => rejectOnce(new Error('Payment was not completed. Your ride has not been published.'))
          }
        });
        checkout.on('payment.failed', (event) => {
          rejectOnce(new Error(event.error?.description || 'Payment failed. Your ride has not been published.'));
        });
        checkout.open();
      });
    }

    function renderRideCard(ride) {
      const driver = Array.isArray(ride.driver) ? ride.driver[0] : ride.driver;
      const name = driver?.full_name || (ride.driver_id === currentUserId ? profileData.name : 'CoRiderly driver');
      const phone = driver?.phone || '';
      const initials = name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join('').toUpperCase() || 'DR';
      const [hours, minutes] = ride.departure_time.split(':').map(Number);
      const isMine = ride.driver_id === currentUserId;
      const card = document.createElement('article');
      card.className = 'ride-card ride-card-modern';
      card.innerHTML = `
        <div class="ride-posted"><span class="ride-travel-date"></span><span>Posted <strong></strong></span></div>
        <div class="ride-route-layout">
          <div class="ride-time-column">
            <strong class="ride-departure-time"></strong>
            <strong class="ride-seat-count"></strong>
          </div>
          <div class="ride-timeline" aria-hidden="true">
            <span class="ride-stop-dot ride-stop-start"></span>
            <span class="ride-stop-line"></span>
            <span class="ride-stop-dot ride-stop-middle"></span>
            <span class="ride-stop-line"></span>
            <span class="ride-stop-dot ride-stop-end"></span>
          </div>
          <div class="ride-stops">
            <strong class="ride-origin"></strong>
            <div class="ride-pickup">
              <span>BOARDING POINT</span>
              <strong></strong>
            </div>
            <strong class="ride-destination"></strong>
          </div>
        </div>
        <div class="ride-driver">
          <div class="ride-driver-avatar"></div>
          <div class="ride-driver-copy">
            <strong class="ride-driver-name"></strong>
            <span class="ride-driver-caption"></span>
          </div>
        </div>
        <div class="ride-card-footer">
          <div class="ride-fare">
            <strong class="ride-fare-amount"></strong>
            <span>/ seat</span>
            <span class="ride-seats-available"></span>
          </div>
          <div class="ride-card-actions">
            <a class="ride-icon-action ride-call-action" aria-label="Call driver" title="Call driver">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.12 4.2 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.12.96.36 1.9.7 2.8a2 2 0 0 1-.45 2.11L8.1 9.9a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.9.34 1.84.58 2.8.7A2 2 0 0 1 22 16.92Z"/></svg>
            </a>
            <a class="ride-icon-action ride-whatsapp-action" aria-label="Message driver on WhatsApp" title="WhatsApp">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20.5 11.5a8.4 8.4 0 0 1-12.4 7.4L3 20l1.2-4.9A8.5 8.5 0 1 1 20.5 11.5Z"/><path d="M8.8 8.2c.2-.5.4-.5.7-.5h.5c.2 0 .4.1.5.4l.7 1.7c.1.2.1.4-.1.6l-.5.6c-.2.2-.2.4 0 .6.6 1 1.5 1.8 2.5 2.2.2.1.4.1.6-.1l.7-.8c.2-.2.4-.2.6-.1l1.6.8c.3.1.4.3.3.6-.1.7-.5 1.3-1.1 1.6-.6.3-1.4.4-2.3.1-1-.3-2.3-1-3.4-2.1-1.2-1.2-2-2.6-2.2-3.5-.2-.8 0-1.5.4-2.1Z"/></svg>
            </a>
            <button class="book-btn ride-owner-button" type="button"></button>
          </div>
        </div>`;
      card.dataset.rideId = ride.id;
      card.dataset.owner = String(isMine);
      card.dataset.price = String(ride.price_per_seat);
      card.dataset.travelDate = ride.travel_date;
      card.dataset.time = String(hours + minutes / 60);
      card.querySelector('.ride-travel-date').textContent = new Date(`${ride.travel_date}T00:00:00`)
        .toLocaleDateString([], { day: 'numeric', month: 'short', year: 'numeric' });
      card.querySelector('.ride-posted strong').textContent = 'Just now';
      card.querySelector('.ride-departure-time').textContent =
        `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
      card.querySelector('.ride-seat-count').textContent =
        `${ride.available_seats} ${ride.available_seats === 1 ? 'seat' : 'seats'}`;
      card.querySelector('.ride-origin').textContent = ride.origin;
      card.querySelector('.ride-stops').classList.add('places');
      card.querySelector('.ride-pickup strong').textContent = ride.pickup_point || 'Pickup point not specified';
      card.querySelector('.ride-destination').textContent = ride.destination;
      card.querySelector('.ride-driver-avatar').textContent = initials;
      card.querySelector('.ride-driver-name').textContent = name;
      card.querySelector('.ride-driver-caption').textContent = isMine ? 'Your ride' : 'CoRiderly member';
      card.querySelector('.ride-fare-amount').textContent = `₹${ride.price_per_seat}`;
      card.querySelector('.ride-seats-available').textContent =
        `${ride.available_seats} ${ride.available_seats === 1 ? 'seat' : 'seats'} available`;
      const bookButton = card.querySelector('.ride-owner-button');
      bookButton.textContent = isMine ? 'Your ride' : 'Book seat';
      bookButton.disabled = isMine;
      if (phone) {
        const normalizedPhone = phone.replace(/[^\d]/g, '');
        const whatsappPhone = normalizedPhone.length === 10
          ? `91${normalizedPhone}`
          : normalizedPhone;
        card.querySelector('.ride-call-action').href = `tel:${phone.replace(/[^\d+]/g, '')}`;
        card.querySelector('.ride-whatsapp-action').href = `https://wa.me/${whatsappPhone}`;
      } else {
        card.querySelector('.ride-call-action').remove();
        card.querySelector('.ride-whatsapp-action').remove();
      }
      return card;
    }

    async function loadRides() {
      const rides = await supabaseRequest(
        'rest/v1/rides?select=*,driver:profiles!rides_driver_id_fkey(full_name,phone)&status=eq.open&order=travel_date.asc,departure_time.asc'
      );
      rideList.replaceChildren(...rides.map(renderRideCard));
      cards = [...rideList.querySelectorAll('.ride-card')];
      document.getElementById('ride-count').textContent = `${cards.length} ${cards.length === 1 ? 'ride' : 'rides'}`;
      document.getElementById('empty').style.display = cards.length ? 'none' : 'block';
    }

    document.getElementById('search-form').addEventListener('submit', (event) => {
      event.preventDefault();
      const from = document.getElementById('from').value.trim().toLowerCase();
      const to = document.getElementById('to').value.trim().toLowerCase();
      const date = document.getElementById('date').value;
      const passengers = Number(document.getElementById('passengers').value || 1);
      let visible = 0;
      cards.forEach((card) => {
        const route = card.querySelector('.places').textContent.toLowerCase();
        const seatCount = Number.parseInt(card.querySelector('.ride-seats-available')?.textContent || '0', 10);
        const matches = (!from || route.includes(from)) &&
          (!to || route.includes(to)) &&
          (!date || card.dataset.travelDate === date) &&
          seatCount >= passengers;
        card.style.display = matches ? '' : 'none';
        if (matches) visible++;
      });
      document.getElementById('ride-count').textContent = `${visible} ${visible === 1 ? 'ride' : 'rides'}`;
      document.getElementById('empty').style.display = visible ? 'none' : 'block';
      if (visible) document.getElementById('rides').scrollIntoView({ behavior: 'smooth', block: 'start' });
    });

    document.getElementById('sort').addEventListener('change', (event) => {
      const key = event.target.value;
      const sorted = [...cards].sort((a, b) => key === 'recommended' ? 0 : Number(a.dataset[key]) - Number(b.dataset[key]));
      sorted.forEach((card) => rideList.appendChild(card));
    });

    const ridesScreen = document.getElementById('rides-screen');
    const offerScreen = document.getElementById('offer-screen');
    const navFind = document.querySelector('.nav a.active');
    const navOffer = document.getElementById('nav-offer');
    const bottomNavTabs = [...document.querySelectorAll('.bottom-nav-tab')];

    function setBottomTab(activeTab) {
      bottomNavTabs.forEach((tab) => {
        const isActive = tab === activeTab;
        tab.classList.toggle('active', isActive);
        if (isActive) {
          tab.setAttribute('aria-current', 'page');
        } else {
          tab.removeAttribute('aria-current');
        }
      });
    }

    function showOfferScreen(showOffer) {
      ridesScreen.classList.toggle('screen-hidden', showOffer);
      offerScreen.classList.toggle('screen-hidden', !showOffer);
      navFind.classList.toggle('active', !showOffer);
      navOffer.classList.toggle('active', showOffer);
      setBottomTab(document.getElementById(showOffer ? 'bottom-offer' : 'bottom-find'));
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    document.getElementById('offer-trigger').addEventListener('click', () => showOfferScreen(true));
    navOffer.addEventListener('click', (event) => {
      event.preventDefault();
      showOfferScreen(true);
    });
    navFind.addEventListener('click', (event) => {
      event.preventDefault();
      showOfferScreen(false);
    });
    document.getElementById('back-to-rides').addEventListener('click', () => showOfferScreen(false));

    document.getElementById('bottom-find').addEventListener('click', () => {
      showOfferScreen(false);
      cards.forEach((card) => { card.style.display = ''; });
      document.getElementById('ride-count').textContent = `${cards.length} ${cards.length === 1 ? 'ride' : 'rides'}`;
      document.getElementById('empty').innerHTML = '<strong>No rides found</strong>Try another city or adjust your search.';
      document.getElementById('empty').style.display = 'none';
    });
    document.getElementById('bottom-offer').addEventListener('click', () => showOfferScreen(true));

    let swipeStart = null;
    const swipeExcludedTargets = 'a, button, input, select, textarea, [contenteditable="true"], .bottom-nav, .topbar, dialog';
    document.getElementById('main-app').addEventListener('touchstart', (event) => {
      if (event.touches.length !== 1 ||
          !(event.target instanceof Element) ||
          event.target.closest(swipeExcludedTargets)) {
        swipeStart = null;
        return;
      }
      const touch = event.touches[0];
      swipeStart = { x: touch.clientX, y: touch.clientY };
    }, { passive: true });
    document.getElementById('main-app').addEventListener('touchend', (event) => {
      if (!swipeStart || event.changedTouches.length !== 1 ||
          document.querySelector('dialog[open]')) {
        swipeStart = null;
        return;
      }
      const touch = event.changedTouches[0];
      const deltaX = touch.clientX - swipeStart.x;
      const deltaY = touch.clientY - swipeStart.y;
      swipeStart = null;
      if (Math.abs(deltaX) < 48 || Math.abs(deltaX) < Math.abs(deltaY) * 1.2) return;
      if (deltaX < 0 && !offerScreen.classList.contains('screen-hidden')) return;
      if (deltaX > 0 && offerScreen.classList.contains('screen-hidden')) return;
      showOfferScreen(deltaX < 0);
    }, { passive: true });
    document.getElementById('main-app').addEventListener('touchcancel', () => {
      swipeStart = null;
    }, { passive: true });

    let authMode = 'register';
    const authHeading = document.getElementById('auth-heading');
    const authSubmit = document.querySelector('#login-form [type="submit"]');
    const authPin = document.getElementById('login-pin');
    const authNote = document.getElementById('login-note');

    function setAuthMode(mode) {
      authMode = mode;
      const registering = mode === 'register';
      document.getElementById('register-mode').classList.toggle('active', registering);
      document.getElementById('register-mode').setAttribute('aria-pressed', String(registering));
      document.getElementById('login-mode').classList.toggle('active', !registering);
      document.getElementById('login-mode').setAttribute('aria-pressed', String(!registering));
      authHeading.textContent = registering ? 'Welcome aboard' : 'Welcome back';
      authSubmit.textContent = registering ? 'Create account' : 'Log in';
      authPin.autocomplete = registering ? 'new-password' : 'current-password';
      authNote.textContent = registering
        ? 'Create an account with your mobile number and a 4-digit MPIN. You can log in after registration.'
        : 'Enter the mobile number and 4-digit MPIN you used to register.';
    }

    document.getElementById('register-mode').addEventListener('click', () => setAuthMode('register'));
    document.getElementById('login-mode').addEventListener('click', () => setAuthMode('login'));

    document.getElementById('login-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      const phone = document.getElementById('login-mobile').value.trim();
      const pin = authPin.value;
      const submitButton = event.currentTarget.querySelector('[type="submit"]');
      submitButton.disabled = true;
      submitButton.textContent = authMode === 'register' ? 'Creating account…' : 'Logging in…';
      try {
        const registering = authMode === 'register';
        const url = `${supabaseUrl}/functions/v1/phone-pin-auth`;
        const name = `Member ${phone.replace(/\D/g, '').slice(-4)}`;
        const response = await fetch(url, {
          method: 'POST',
          headers: { apikey: supabaseAnonKey, 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: registering ? 'register' : 'login', phone, pin })
        });
        const result = await response.json();
        if (!response.ok) throw new Error(result.msg || result.message || result.error_description || (registering ? 'Could not create your account.' : 'Could not log in.'));
        if (registering) {
          setAuthMode('login');
          authNote.textContent = 'Account created. Log in with your mobile number and 4-digit MPIN.';
          showToast('Account created. You can log in now.');
          return;
        }
        if (!result.access_token || !result.userId) {
          throw new Error('Login succeeded without a usable session. Please try again.');
        }
        accessToken = result.access_token;
        currentUserId = result.userId;
        profileData = {
          ...profileData,
          name,
          email: '',
          phone
        };
        try { localStorage.setItem(profileStorageKey, JSON.stringify(profileData)); } catch (error) { /* Keep this session's profile in memory. */ }
        await supabaseRequest('rest/v1/profiles?on_conflict=id', {
          method: 'POST',
          headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
          body: JSON.stringify({ id: currentUserId, full_name: name, phone })
        });
        await loadRides();
        updateProfileDisplay();
        document.getElementById('splash-screen').hidden = true;
        document.getElementById('main-app').hidden = false;
        authPin.value = '';
        showOfferScreen(false);
      } catch (error) {
        authNote.textContent = error.message;
        showToast(error.message);
      } finally {
        submitButton.disabled = false;
        submitButton.textContent = authMode === 'register' ? 'Create account' : 'Log in';
      }
    });

    const profileButton = document.getElementById('profile-button');
    const profileMenu = document.getElementById('profile-menu');
    profileButton.addEventListener('click', () => {
      const isOpen = !profileMenu.hidden;
      profileMenu.hidden = isOpen;
      profileButton.setAttribute('aria-expanded', String(!isOpen));
    });
    document.addEventListener('click', (event) => {
      if (!event.target.closest('.profile-area')) {
        profileMenu.hidden = true;
        profileButton.setAttribute('aria-expanded', 'false');
      }
    });
    function openProfileEditor() {
      profileMenu.hidden = true;
      profileButton.setAttribute('aria-expanded', 'false');
      document.getElementById('profile-edit-name').value = profileData.name;
      document.getElementById('profile-edit-email').value = profileData.email;
      document.getElementById('profile-edit-phone').value = profileData.phone;
      document.getElementById('profile-dialog').showModal();
    }
    function signOut() {
      accessToken = null;
      currentUserId = null;
      pendingRideId = null;
      pendingRideDetails = null;
      authPin.value = '';
      setAuthMode('login');
      authNote.textContent = 'You have been logged out. Enter your mobile number and 4-digit MPIN to log in again.';
      profileMenu.hidden = true;
      profileButton.setAttribute('aria-expanded', 'false');
      const profileDialog = document.getElementById('profile-dialog');
      if (profileDialog.open) profileDialog.close();
      document.getElementById('main-app').hidden = true;
      document.getElementById('splash-screen').hidden = false;
    }
    document.getElementById('edit-profile-action').addEventListener('click', openProfileEditor);
    document.getElementById('profile-logout-menu').addEventListener('click', signOut);
    document.getElementById('profile-logout-dialog').addEventListener('click', signOut);
    document.getElementById('bottom-profile').addEventListener('click', (event) => {
      openProfileEditor();
      setBottomTab(event.currentTarget);
    });
    document.getElementById('profile-form').addEventListener('submit', (event) => {
      event.preventDefault();
      profileData = {
        name: document.getElementById('profile-edit-name').value.trim(),
        email: document.getElementById('profile-edit-email').value.trim(),
        phone: document.getElementById('profile-edit-phone').value.trim()
      };
      try { localStorage.setItem(profileStorageKey, JSON.stringify(profileData)); } catch (error) { /* Keep this session's profile in memory. */ }
      updateProfileDisplay();
      document.getElementById('profile-dialog').close();
      showToast('Profile updated.');
    });
    document.querySelectorAll('[data-close-dialog]').forEach((button) => {
      button.addEventListener('click', () => document.getElementById(button.dataset.closeDialog).close());
    });
    function showMyRides() {
      showOfferScreen(false);
      setBottomTab(document.getElementById('bottom-my-rides'));
      let visible = 0;
      cards.forEach((card) => {
        const isMine = card.dataset.owner === 'true';
        card.style.display = isMine ? '' : 'none';
        if (isMine) visible++;
      });
      document.getElementById('ride-count').textContent = `${visible} ${visible === 1 ? 'ride' : 'rides'}`;
      document.getElementById('empty').innerHTML = '<strong>No rides offered yet</strong>Your published rides will appear here.';
      document.getElementById('empty').style.display = visible ? 'none' : 'block';
    }
    document.getElementById('bottom-my-rides').addEventListener('click', showMyRides);
    function showMyBookings() {
      setBottomTab(document.getElementById('bottom-bookings'));
      const list = document.getElementById('booking-list');
      list.replaceChildren();
      if (!bookings.length) {
        const emptyMessage = document.createElement('div');
        emptyMessage.className = 'booking-empty';
        emptyMessage.textContent = 'You haven\'t booked a seat yet.';
        list.append(emptyMessage);
      } else {
        bookings.forEach((booking) => {
          const item = document.createElement('div');
          item.className = 'booking-item';
          const route = document.createElement('strong');
          route.textContent = booking.route;
          const details = document.createElement('span');
          details.textContent = `${booking.time} · ${booking.price}`;
          item.append(route, details);
          list.append(item);
        });
      }
      document.getElementById('bookings-dialog').showModal();
    }
    document.getElementById('bottom-bookings').addEventListener('click', showMyBookings);

    const carCapacity = document.getElementById('offer-car-seats');
    const passengerSeats = document.getElementById('offer-seats');
    carCapacity.addEventListener('change', () => {
      const maxPassengerSeats = Number(carCapacity.value) - 1;
      passengerSeats.max = String(maxPassengerSeats);
      if (Number(passengerSeats.value) > maxPassengerSeats) passengerSeats.value = String(maxPassengerSeats);
    });
    document.getElementById('offer-form').addEventListener('reset', () => {
      window.setTimeout(() => { passengerSeats.max = String(Number(carCapacity.value) - 1); }, 0);
    });

    document.getElementById('offer-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      const submitButton = event.currentTarget.querySelector('[type="submit"]');
      submitButton.disabled = true;
      submitButton.textContent = 'Preparing payment…';
      try {
      const value = (id) => document.getElementById(id).value.trim();
      const from = value('offer-from');
      const to = value('offer-to');
      const phone = value('offer-phone');
      const seats = value('offer-seats');
      const carName = value('offer-car-name');
      const carNumber = value('offer-car-number');
      const carSeats = value('offer-car-seats');
      const price = value('offer-price');
      const departure = value('offer-time');
      const date = value('offer-date');
      const pickup = value('offer-pickup');
      const bags = value('offer-bags');
      if (!accessToken || !currentUserId) {
        throw new Error('Please log in before publishing a ride.');
      }
      const ride = {
        origin: from,
        destination: to,
        pickup_point: pickup || null,
        travel_date: date,
        departure_time: departure,
        car_model: carName,
        car_registration: carNumber,
        car_capacity: Number(carSeats),
        available_seats: Number(seats),
        bags: Number(bags || 0),
        price_per_seat: Number(price)
      };
      const samePendingRide = pendingRideId &&
        JSON.stringify(ride) === JSON.stringify(pendingRideDetails);
      const order = await ridePaymentRequest({
        action: 'create_order',
        ride,
        ...(samePendingRide ? { ride_id: pendingRideId } : {})
      });
      if (order.already_paid) {
        pendingRideId = null;
        pendingRideDetails = null;
        await loadRides();
        showOfferScreen(false);
        showToast('₹39 payment confirmed. Your ride is published.');
        event.target.reset();
        return;
      }
      pendingRideId = order.ride_id;
      pendingRideDetails = ride;
      submitButton.textContent = 'Complete ₹39 payment…';
      await loadRazorpayCheckout();
      const paymentResult = await openRidePaymentCheckout(order, phone);
      const savedRide = paymentResult;
      pendingRideId = null;
      pendingRideDetails = null;
      const [hour, minute] = departure.split(':').map(Number);
      const displayTime = new Date(2000, 0, 1, hour, minute).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
      const card = document.createElement('article');
      card.className = 'ride-card';
      card.dataset.rideId = savedRide.id;
      card.dataset.owner = 'true';
      card.dataset.price = price;
      card.dataset.time = hour + minute / 60;
      card.innerHTML = '<div class="route"><div class="times"><span class="departure-time"></span><span class="seat-count"></span></div><div class="route-track"><i class="dot"></i><i class="track-line"></i><i class="dot end"></i></div><div class="places"><span class="place from-place"></span><span class="place to-place"></span></div></div><div class="ride-meta"><div class="meta-row ride-date"></div><div class="meta-row ride-extras"></div></div><div class="driver"><div class="driver-avatar">AM</div><div><div class="driver-name">Alex Morgan</div></div></div><div class="price-col"><div><div class="price ride-price"></div><div class="seats"></div></div><div class="ride-actions"><button class="book-btn" type="button">Book seat</button><a class="call-btn" aria-label="Call driver"><svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.12 4.2 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.12.96.36 1.9.7 2.8a2 2 0 0 1-.45 2.11L8.1 9.9a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.9.34 1.84.58 2.8.7A2 2 0 0 1 22 16.92Z"/></svg>Call</a></div></div>';
      card.querySelector('.driver-name').textContent = profileData.name;
      card.querySelector('.driver-avatar').textContent = profileData.name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join('').toUpperCase() || 'AM';
      card.querySelector('.departure-time').textContent = displayTime;
      card.querySelector('.seat-count').textContent = `${seats} seats`;
      card.querySelector('.from-place').textContent = from;
      card.querySelector('.to-place').textContent = to;
      card.querySelector('.ride-date').textContent = `Travel date: ${date}`;
      card.querySelector('.ride-extras').textContent = `${carName} · ${carSeats}-seater · ${carNumber}${pickup ? ` · Pickup: ${pickup}` : ''} · ${bags} bags`;
      card.querySelector('.ride-price').textContent = `₹${price}`;
      card.querySelector('.ride-price').append(document.createElement('small'));
      card.querySelector('.ride-price small').textContent = ' / seat';
      card.querySelector('.seats').textContent = `${seats} seats available`;
      const contact = document.createElement('a');
      contact.href = `tel:${phone.replace(/[^+\d]/g, '')}`;
      contact.setAttribute('aria-label', `Call driver at ${phone}`);
      contact.innerHTML = '<svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.12 4.2 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.12.96.36 1.9.7 2.8a2 2 0 0 1-.45 2.11L8.1 9.9a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.9.34 1.84.58 2.8.7A2 2 0 0 1 22 16.92Z"/></svg>';
      card.querySelector('.call-btn').href = contact.href;
      card.querySelector('.call-btn').setAttribute('aria-label', contact.getAttribute('aria-label'));
      rideList.prepend(renderRideCard({
        ...savedRide,
        created_at: new Date().toISOString(),
        driver: { full_name: profileData.name, phone }
      }));
      cards = [...rideList.querySelectorAll('.ride-card')];
      cards.forEach((ride) => { ride.style.display = ''; });
      document.getElementById('ride-count').textContent = `${cards.length} ${cards.length === 1 ? 'ride' : 'rides'}`;
      document.getElementById('empty').style.display = 'none';
      document.getElementById('offer-success').style.display = 'block';
      showOfferScreen(false);
      showToast('₹39 payment confirmed. Your ride is published.');
      event.target.reset();
      } catch (error) {
        showToast(error.message);
      } finally {
        submitButton.disabled = false;
        submitButton.textContent = 'Pay ₹39 & publish ride';
      }
    });

    rideList.addEventListener('click', (event) => {
      const button = event.target.closest('.book-btn');
      if (!button) return;
      const card = button.closest('.ride-card');
      const existingIndex = bookings.findIndex((booking) => booking.card === card);
      if (existingIndex >= 0) {
        bookings.splice(existingIndex, 1);
        button.textContent = 'Book seat';
        button.removeAttribute('aria-pressed');
        showToast('Booking removed.');
        return;
      }
      const places = [...card.querySelectorAll('.place')].map((place) => place.textContent.trim());
      const time = card.querySelector('.times span')?.textContent.trim() || 'Departure time unavailable';
      const price = card.querySelector('.price')?.textContent.trim() || 'Price unavailable';
      bookings.push({ card, route: places.join(' → '), time, price });
      button.textContent = 'Booked';
      button.setAttribute('aria-pressed', 'true');
      showToast('Seat booked — find it under My bookings.');
    });