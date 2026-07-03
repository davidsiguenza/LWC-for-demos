import { createElement } from 'lwc';
import ScheduleAppointment from 'c/scheduleAppointment';

describe('c-schedule-appointment', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the default button label', () => {
        const el = createElement('c-schedule-appointment', { is: ScheduleAppointment });
        document.body.appendChild(el);
        const btn = el.shadowRoot.querySelector('lightning-button');
        expect(btn).toBeTruthy();
        expect(btn.label).toBe('Schedule an appointment');
    });

    it('uses custom button label when provided', () => {
        const el = createElement('c-schedule-appointment', { is: ScheduleAppointment });
        el.buttonLabel = 'Book a visit';
        document.body.appendChild(el);
        const btn = el.shadowRoot.querySelector('lightning-button');
        expect(btn.label).toBe('Book a visit');
    });

    it('opens modal when button is clicked', async () => {
        const el = createElement('c-schedule-appointment', { is: ScheduleAppointment });
        document.body.appendChild(el);
        const btn = el.shadowRoot.querySelector('lightning-button');
        btn.click();
        await Promise.resolve();
        const modal = el.shadowRoot.querySelector('.scheduler-modal');
        expect(modal).toBeTruthy();
    });
});
