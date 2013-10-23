import 'package:polymer/polymer.dart';
import 'dart:html';

import 'package:tapo_calendar/calendarview/calendarview.dart';

@CustomTag('tapo-calendar-eventlist')
class EventListElement extends PolymerElement {
  
  EventListElement.created() : super.created();
  
  CalendarView get calendarView =>
      this.getShadowRoot('tapo-calendar-eventlist').querySelector('tapo-calendar-calendarview');
  
  void clickedZoomIn() {
    calendarView.zoomIn();
  }
  void clickedZoomOut() {
    calendarView.zoomOut();
  }
  
  void enteredView() {
    super.enteredView();
    
    print("hello world.");
    print("entered view.. ${calendarView}");
    DateTime date = new DateTime.now();
    DateTime start = new DateTime(date.year, date.month, date.day, 7);
    DateTime end = new DateTime(date.year, date.month, date.day, 7, 45);
    calendarView.events = [new CalendarEvent(1, start, end, title, 'uh yeah.')];
  }
}