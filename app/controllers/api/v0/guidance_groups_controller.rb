module Api
  module V0
    class GuidanceGroupsController  < Api::V0::BaseController
      before_action :authenticate

      swagger_controller :guidance_groupss, 'Guidance Groups'

      swagger_api :show do
        summary 'Returns a single guidance group item'
        notes   'Notes...'
        param :path, :id, :integer, :required, "Guidance Group Id"
        param :header, 'Authorization Token', :string, :required, 'Authorization-Token'
        response :ok, "success", :Guidance
        response :unauthorized
        response :not_found
      end

      # TODO: impliment auth on show/index
      # for both, first validate that the user has the permission to use this api
      # then for show, display iff they have permissions for that resource
      # for index, compile the list of all groups they have permissions to view, then return

      def show
        # check if the user has permission to use the guidances api
        if has_auth("guidances")
          # determine if they have authorization to view this guidance group
          if GuidanceGroup.can_view?(@user, params[:id])
            respond_with get_resource
          else
            render json: I18n.t("api.bad_resource"), status: 401
          end
        else
          render json: I18n.t("api.no_auth_for_endpoint"), status: 401
        end
      end

      swagger_api :index do
        summary 'Returns a list of all viewable guidances'
        notes   'Notes...'
        param :header, 'Authentication-Token', :string, :required, 'Authentication-Token'
        response :unauthorized
      end


      def index

        if has_auth("guidances")
          @all_viewable_groups = GuidanceGroup.all_viewable(@user)
          respond_with @all_viewable_groups
        else
          #render unauthorised
          render json: I18n.t("api.no_auth_for_endpoint"), status: 401
        end
      end


      private
        def query_params
          params.permit(:id)
        end

    end
  end
end
