import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getPersonAccountId from '@salesforce/apex/ScheduleAppointmentController.getPersonAccountId';
import getProductName from '@salesforce/apex/ScheduleAppointmentController.getProductName';
import saveBooking from '@salesforce/apex/ScheduleAppointmentController.saveBooking';

const SLOT_START = 10;
const SLOT_COUNT = 8;
const MONTHS = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
];

function toYYYYMMDD(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}

function parseDate(str) {
    const [y, m, d] = str.split('-').map(Number);
    return new Date(y, m - 1, d);
}

function formatDisplayDate(str) {
    const d = parseDate(str);
    return `${MONTHS[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
}

function slotLabel(hour) {
    const h2 = String(hour + 1).padStart(2, '0');
    const h1 = String(hour).padStart(2, '0');
    return `${h1}:00 - ${h2}:00`;
}

/**
 * Deterministic "mock" filled slots per date: 1–2 slots per day.
 */
function getMockFilledIndices(dateStr) {
    let n = 0;
    for (let i = 0; i < dateStr.length; i++) {
        n = (n * 31 + dateStr.charCodeAt(i)) >>> 0;
    }
    const i1 = n % SLOT_COUNT;
    let i2 = ((n * 7) + 1) % SLOT_COUNT;
    if (i2 === i1) {
        i2 = (i1 + 1) % SLOT_COUNT;
    }
    return [i1, i2];
}

/**
 * Extract user-facing message from Apex/LWC error (handles 400, AuraHandledException, etc.).
 */
function getApexErrorMessage(error) {
    if (!error) return 'An unexpected error occurred.';
    const b = error.body;
    if (b) {
        if (Array.isArray(b) && b[0]?.message) return b[0].message;
        if (Array.isArray(b?.pageErrors) && b.pageErrors[0]?.message) return b.pageErrors[0].message;
        if (typeof b.message === 'string') return b.message;
        if (typeof b === 'string') return b;
    }
    if (typeof error.message === 'string') return error.message;
    return 'Failed to save booking.';
}

/** Product2 Id prefix; used to treat recordId as product when on PDP. */
const PRODUCT_PREFIX = '01t';

export default class ScheduleAppointment extends LightningElement {
    @api buttonLabel = 'Schedule an appointment';
    @api productId = '';
    @api productName = '';

    personAccountId;
    loginRequired = false;
    pageRecordId = null;
    showModal = false;
    showSlots = false;
    selectedDate = null;
    viewYear = null;
    viewMonth = null;
    errorMessage = '';
    /** Set of 'date|label' for user-booked slots */
    _booked = new Set();

    @wire(getPersonAccountId)
    wiredAccountId({ data, error }) {
        if (error) {
            this.errorMessage = error?.body?.message || 'Failed to load account.';
            return;
        }
        this.personAccountId = data;
        this.loginRequired = !data;
        this.errorMessage = '';
    }

    @wire(CurrentPageReference)
    wiredPageRef(ref) {
        if (!ref) return;
        const rid = ref.attributes?.recordId || ref.state?.recordId;
        if (rid && typeof rid === 'string' && rid.length >= 15 && rid.startsWith(PRODUCT_PREFIX)) {
            this.pageRecordId = rid;
        } else {
            this.pageRecordId = null;
        }
    }

    get calendarTitle() {
        if (this.viewYear == null || this.viewMonth == null) return '';
        return `${MONTHS[this.viewMonth]} ${this.viewYear}`;
    }

    get selectedDateLabel() {
        return this.selectedDate ? formatDisplayDate(this.selectedDate) : '';
    }

    get calendarDays() {
        if (this.viewYear == null || this.viewMonth == null) return [];
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const first = new Date(this.viewYear, this.viewMonth, 1);
        const last = new Date(this.viewYear, this.viewMonth + 1, 0);
        const startWeekday = first.getDay();
        const days = [];
        for (let i = 0; i < startWeekday; i++) {
            days.push({
                key: `pad-${i}`,
                padding: true,
                dateStr: '',
                dayNum: '',
                disabled: true,
                dayClass: 'day-cell day-padding'
            });
        }
        for (let d = 1; d <= last.getDate(); d++) {
            const date = new Date(this.viewYear, this.viewMonth, d);
            const dateStr = toYYYYMMDD(date);
            const disabled = date < today;
            const dayClass = `day-cell${disabled ? ' day-disabled' : ''}`;
            days.push({
                key: dateStr,
                padding: false,
                dateStr,
                dayNum: d,
                disabled,
                dayClass
            });
        }
        return days;
    }

    get slotOptions() {
        if (!this.selectedDate) return [];
        const filled = getMockFilledIndices(this.selectedDate);
        const slots = [];
        for (let i = 0; i < SLOT_COUNT; i++) {
            const hour = SLOT_START + i;
            const label = slotLabel(hour);
            const key = `${this.selectedDate}|${label}`;
            const filledSlot = filled.includes(i);
            const booked = this._booked.has(key);
            const selected = booked;
            const filledOrBooked = filledSlot || booked;
            let slotClass = 'slot-cell';
            if (filledSlot) slotClass += ' slot-filled';
            if (booked) slotClass += ' slot-booked';
            if (selected) slotClass += ' slot-selected';
            let status = 'available';
            if (filledSlot) status = 'filled';
            else if (booked) status = 'booked';
            slots.push({
                key,
                label,
                filled: filledSlot,
                booked,
                selected,
                filledOrBooked,
                slotClass,
                ariaLabel: `${label}, ${status}`
            });
        }
        return slots;
    }

    get todayStr() {
        return toYYYYMMDD(new Date());
    }

    get showSlotsAndLoggedIn() {
        return !this.loginRequired && this.showSlots;
    }

    get showCalendar() {
        return !this.loginRequired && !this.showSlots;
    }

    handleOpenScheduler() {
        this.errorMessage = '';
        const now = new Date();
        this.viewYear = now.getFullYear();
        this.viewMonth = now.getMonth();
        this.selectedDate = null;
        this.showSlots = false;
        this.showModal = true;
    }

    handleCloseModal() {
        this.showModal = false;
        this.showSlots = false;
        this.selectedDate = null;
        this.errorMessage = '';
    }

    handlePrevMonth() {
        if (this.viewMonth === 0) {
            this.viewMonth = 11;
            this.viewYear -= 1;
        } else {
            this.viewMonth -= 1;
        }
    }

    handleNextMonth() {
        if (this.viewMonth === 11) {
            this.viewMonth = 0;
            this.viewYear += 1;
        } else {
            this.viewMonth += 1;
        }
    }

    handleSelectDate(event) {
        const dateStr = event.currentTarget?.dataset?.date;
        if (!dateStr) return;
        this.selectedDate = dateStr;
        this.showSlots = true;
    }

    handleBackToCalendar() {
        this.showSlots = false;
        this.selectedDate = null;
    }

    async handleSelectSlot(event) {
        const el = event.currentTarget;
        const filled = el.dataset.slotFilled === 'true';
        const booked = el.dataset.slotBooked === 'true';
        if (filled || booked) return;
        const label = el.dataset.slotLabel;
        const key = el.dataset.slotKey;
        if (!this.selectedDate || !label || !key) return;
        if (this.loginRequired || !this.personAccountId) {
            this.errorMessage = 'Please log in to schedule an appointment.';
            return;
        }
        this.errorMessage = '';
        let productId = (this.productId && this.productId.trim()) || null;
        let productName = (this.productName && this.productName.trim()) || null;
        if (!productId && this.pageRecordId) productId = this.pageRecordId;
        if (productId && !productName) {
            try {
                productName = await getProductName({ productId });
            } catch (_) {
                productName = null;
            }
        }
        try {
            await saveBooking({
                dateStr: this.selectedDate,
                slotLabel: label,
                productId: productId || undefined,
                productName: productName || undefined
            });
            this._booked = new Set([...this._booked, key]);
        } catch (e) {
            this.errorMessage = getApexErrorMessage(e);
        }
    }

    handleSlotKeydown(event) {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        this.handleSelectSlot(event);
    }
}
