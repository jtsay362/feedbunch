########################################################
# AngularJS service to load user configuration data in the scope.
########################################################

angular.module('feedbunch').service 'userDataSvc',
['$rootScope', '$http', 'timerFlagSvc',
($rootScope, $http, timerFlagSvc)->

  #---------------------------------------------
  # Load user configuration data via AJAX into the root scope
  #---------------------------------------------
  load_data: ->
    now = new Date()
    $http.get("/api/user_data.json?time=#{now.getTime()}")
    .success (data)->
      $rootScope.open_all_entries = data["open_all_entries"]
      $rootScope.quick_reading = data["quick_reading"]
      $rootScope.subscribed_feeds_count = data["subscribed_feeds_count"]
    .error (data, status)->
      timerFlagSvc.start 'error_loading_user_data' if status!=0
]