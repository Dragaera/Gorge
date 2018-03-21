# coding: utf-8

module Gorge
  module Web
    class API < Grape::API
      logger Gorge.logger(program: 'api', module_: 'players')
      use GrapeLogging::Middleware::RequestLogger, { logger: Gorge.logger(program: 'api', module_: 'requests') }

      helpers do
        def logger
          API.logger
        end
      end

      format :json

      resource :players do

        desc "Return a player's statistics"
        params do
          requires :steam_id, type: Integer, desc: 'Steam ID'
        end
        route_param :steam_id do
          get :statistics do
            player = Player.first(steam_id: params[:steam_id])

            if player
              {
                steam_id: player.steam_id,

                kdr: {
                  total: player.kdr,
                  alien: player.alien_kdr,
                  marine: player.marine_kdr,
                },

                accuracy: {
                  total: player.accuracy,
                  alien: player.alien_accuracy,
                  marine: {
                    total: player.marine_accuracy,
                    no_onos: player.marine_accuracy(include_onos: false),
                  },
                }
              }
            else
              error! 'No such player', 404
            end
          end
        end
      end
    end
  end
end