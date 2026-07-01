enum CallControl {
  mute('Mute'),
  speaker('Speaker'),
  keypad('Keypad'),
  bluetooth('Bluetooth'),
  hold('Hold'),
  transfer('Transfer'),
  addParticipant('Add Participant'),
  recordCall('Record Call'),
  voicemail('Voicemail'),
  callNotes('Call Notes');

  const CallControl(this.label);

  final String label;
}
