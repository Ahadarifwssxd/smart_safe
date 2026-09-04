import 'package:flutter/material.dart';

class MenuAppController extends ChangeNotifier {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  String _selectedRouteKey = 'dashboard';
  String _searchQuery = '';

  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;
  int get selectedIndex => _selectedIndex;
  String get selectedRouteKey => _selectedRouteKey;
  String get searchQuery => _searchQuery;

  void controlMenu() {
    if (!_scaffoldKey.currentState!.isDrawerOpen) {
      _scaffoldKey.currentState!.openDrawer();
    }
  }

  void setSelectedIndex(int index) {
    _selectedIndex = index;
    notifyListeners();
  }

  void setSelectedRoute(String routeKey, {int? menuIndex}) {
    _selectedRouteKey = routeKey;
    if (menuIndex != null) _selectedIndex = menuIndex;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }
}
