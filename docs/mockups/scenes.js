// ox_lib-style scenes that are not part of the tablet (job offer pop-up, driving HUD)
const SCENES = {
  '14-job-offer': {
    alert: {
      header: 'Job offer',
      content: '**Rourke Freight Lines** wants to hire you as a **Driver** for **$1,200** per 60-minute shift.\n\nAccept?',
      cancel: 'Decline', confirm: 'Accept',
    },
    caption: ['What the player sees', 'Accepting adds them to the roster. Wages pile up as a paycheck at the office time clock.'],
  },

  '15-driving': {
    bg: 'road',
    textui: '[E] Deliver load',
    notify: [{ type: 'warning', text: 'Deadline: 14m 20s. Late deliveries pay less.' }],
    caption: ['Player drivers really drive', 'Grab the truck at the yard, hook the trailer at the port, follow the route, deliver, then bring the truck back.'],
  },

  '16-unloading': {
    bg: 'road',
    progress: { pct: 64, label: 'Unloading...' },
    notify: [{ type: 'success', text: 'Delivered! Company earned $8,650, your cut: $1,297. Return the truck to the yard.' }],
    caption: ['Validated deliveries', 'The server checks positions and travel time. Cargo damage reduces the payout, and drivers earn a commission.'],
  },
};
