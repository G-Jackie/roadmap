module OrgAdmin
  class TemplatesController < ApplicationController
    include Paginable
    after_action :verify_authorized

    # GET /org_admin/templates
    # -----------------------------------------------------
    def index
      authorize Template
      valid_orgs = current_user.can_super_admin? ? Org.not_funder : Org.find(current_user.org)
      org_templates = Template.get_latest_template_versions(valid_orgs).page(1)
      funder_templates = Template.get_latest_template_versions(Org.funder).page(1)

      # If the user is an Org Admin look for customizations to funder templates
      customizations = {}
      if current_user.can_org_admin?
        funder_templates.each do |funder_template|
          customization = Template.org_customizations(funder_template.dmptemplate_id, current_user.org_id)
          customizations[customization.customization_of] = customization if customization.present?
        end
      end

      # Gather up all of the publication dates for the live versions of each template.
      published = {}
      [funder_templates, org_templates].each do |collection|
        collection.each do |template|
          live = Template.live(template.dmptemplate_id)
          published[template.dmptemplate_id] = live.updated_at if live.present?
        end
      end
      
      render 'index', locals: {
        funder_templates: funder_templates, 
        org_templates: org_templates,
        customized_templates: customizations,
        published: published,
        current_org: current_user.org, 
        orgs: Org.all
      }
    end
    
    # GET /org_admin/templates/new
    # -----------------------------------------------------
    def new
      authorize Template
    end
    
    # POST /org_admin/templates
    # -----------------------------------------------------
    def create
      authorize Template
      # creates a new template with version 0 and new dmptemplate_id
      @template = Template.new(params[:template])
      @template.org_id = current_user.org.id
      @template.description = params['template-desc']
      @template.links = (params["template-links"].present? ? JSON.parse(params["template-links"]) : {"funder": [], "sample_plan": []})

      if @template.save
        redirect_to edit_org_admin_template_path(@template), notice: success_message(_('template'), _('created'))
      else
        @hash = @template.to_hash
        flash[:alert] = failed_create_error(@template, _('template'))
        render action: "new"
      end
    end
    
    # GET /org_admin/templates/:id/edit
    # -----------------------------------------------------
    def edit
      @template = Template.includes(:org, phases: [sections: [questions: [:question_options, :question_format, :annotations]]]).find(params[:id])
      authorize @template

      @current = Template.current(@template.dmptemplate_id)

      if @template == @current
        # If the template is published
        if @template.published?
          # We need to create a new, editable version
          new_version = Template.deep_copy(@template)
          new_version.version = (@template.version + 1)
          new_version.published = false
          new_version.save
          @template = new_version
  #        @current = Template.current(@template.dmptemplate_id)
        end
      else
        flash[:notice] = _('You are viewing a historical version of this template. You will not be able to make changes.')
      end

      # If the template is published
      if @template.published?
        # We need to create a new, editable version
        new_version = Template.deep_copy(@template)
        new_version.version = (@template.version + 1)
        new_version.published = false
        new_version.save
        @template = new_version
      end

      # once the correct template has been generated, we convert it to hash
      @template_hash = @template.to_hash
      render('container',
        locals: { 
          partial_path: 'edit',
          template: @template,
          current: @current,
          template_hash: @template_hash
        })
    end
    
    # PUT /org_admin/templates/:id
    # -----------------------------------------------------
    def update
      @template = Template.find(params[:id])
      authorize @template

      current = Template.current(@template.dmptemplate_id)

      # Only allow the current version to be updated
      if current != @template
        redirect_to edit_org_admin_template_path(@template), notice: _('You can not edit a historical version of this template.')

      else
        if @template.description != params["template-desc"] ||
                @template.title != params[:template][:title]
          @template.dirty = true
        end

        @template.description = params["template-desc"]
        @template.links = JSON.parse(params["template-links"]) if params["template-links"].present?
      
        # If the visibility checkbox is not checked and the user's org is a funder set the visibility to public
        # otherwise default it to organisationally_visible
        if current_user.org.funder? && params[:template_visibility].nil?
          @template.visibility = Template.visibilities[:publicly_visible]
        else
          @template.visibility = Template.visibilities[:organisationally_visible]
        end
      
        if @template.update_attributes(params[:template])
          flash[:notice] = success_message(_('template'), _('saved'))

        else
          flash[:alert] = failed_update_error(@template, _('template'))
        end

        redirect_to action: 'edit', id: params[:id]
      end
    end
    
    # DELETE /org_admin/templates/:id
    # -----------------------------------------------------
    def destroy
      @template = Template.find(params[:id])
      authorize @template

      if @template.plans.length <= 0
        current = Template.current(@template.dmptemplate_id)

        # Only allow the current version to be destroyed
        if current == @template
          if @template.destroy
            flash[:notice] = success_message(_('template'), _('removed'))
            redirect_to org_admin_templates_path
          else
            @hash = @template.to_hash
            flash[:alert] = failed_destroy_error(@template, _('template'))
            render org_admin_templates_path
          end
        else
          flash[:alert] = _('You cannot delete historical versions of this template.')
          redirect_to org_admin_templates_path
        end
      else
        flash[:alert] = _('You cannot delete a template that has been used to create plans.')
        redirect_to org_admin_templates_path
      end
    end

    # GET /org_admin/templates/:id/history
    # -----------------------------------------------------
    def history
      @template = Template.find(params[:id])
      authorize @template
      @templates = Template.where(dmptemplate_id: @template.dmptemplate_id).order(:version)
      @current = Template.current(@template.dmptemplate_id)
    end
    
    # GET /org_admin/templates/:id/customize
    # -----------------------------------------------------
    def customize
      @template = Template.find(params[:id])
      authorize @template

      customisation = Template.deep_copy(@template)
      customisation.org = current_user.org
      customisation.version = 0
      customisation.customization_of = @template.dmptemplate_id
      customisation.dmptemplate_id = loop do
        random = rand 2147483647
        break random unless Template.exists?(dmptemplate_id: random)
      end
      customisation.dirty = true
      customisation.save

      customisation.phases.includes(:sections, :questions).each do |phase|
        phase.modifiable = false
        phase.save!
        phase.sections.each do |section|
          section.modifiable = false
          section.save!
          section.questions.each do |question|
            question.modifiable = false
            question.save!
          end
        end
      end

      redirect_to edit_org_admin_template_path(customisation)
    end

    # GET /org_admin/templates/:id/transfer_customization
    # the funder template's id is passed through here
    # -----------------------------------------------------
    def transfer_customization
      @template = Template.includes(:org).find(params[:id])
      authorize @template
      new_customization = Template.deep_copy(@template)
      new_customization.org_id = current_user.org_id
      new_customization.published = false
      new_customization.customization_of = @template.dmptemplate_id
      new_customization.dirty = true
      new_customization.phases.includes(sections: :questions).each do |phase|
        phase.modifiable = false
        phase.save
        phase.sections.each do |section|
          section.modifiable = false
          section.save
          section.questions.each do |question|
            question.modifiable = false
            question.save
          end
        end
      end
      customizations = Template.includes(:org, phases:[sections: [questions: :annotations]]).where(org_id: current_user.org_id, customization_of: @template.dmptemplate_id).order(version: :desc)
      # existing version to port over
      max_version = customizations.first
      new_customization.dmptemplate_id = max_version.dmptemplate_id
      new_customization.version = max_version.version + 1
      # here we rip the customizations out of the old template
      # First, we find any customzed phases or sections
      max_version.phases.each do |phase|
        # check if the phase was added as a customization
        if phase.modifiable
          # deep copy the phase and add it to the template
          phase_copy = Phase.deep_copy(phase)
          phase_copy.number = new_customization.phases.length + 1
          phase_copy.template_id = new_customization.id
          phase_copy.save!
        else
          # iterate over the sections to see if any of them are customizations
          phase.sections.each do |section|
            if section.modifiable
              # this is a custom section
              section_copy = Section.deep_copy(section)
              customization_phase = new_customization.phases.includes(:sections).where(number: phase.number).first
              section_copy.phase_id = customization_phase.id
              # custom sections get added to the end
              section_copy.number = customization_phase.sections.length + 1
              # section from phase with corresponding number in the main_template
              section_copy.save!
            else
              # not a customized section, iterate over questions
              customization_phase = new_customization.phases.includes(sections: [questions: :annotations]).where(number: phase.number).first
              customization_section = customization_phase.sections.where(number: section.number).first
              section.questions.each do |question|
                # find corresponding question in new template
                customization_question = customization_section.questions.where(number: question.number).first
                # apply annotations
                question.annotations.where(org_id: current_user.org_id).each do |annotation|
                  annotation_copy = Annotation.deep_copy(annotation)
                  annotation_copy.question_id = customization_question.id
                  annotation_copy.save!
                end
              end
            end
          end
        end
      end
      new_customization.save
      redirect_to edit_org_admin_template_path(new_customization)
    end
    
    
    # GET /org_admin/templates/funders/:page  (AJAX)
    # -----------------------------------------------------
    def funders
      authorize Template
      if params[:page] == 'ALL'
        templates = Template.get_latest_template_versions(Org.funder)
      else
        templates = Template.get_latest_template_versions(Org.funder).page(params[:page])
      end
      # Include the default template in the list of funder templates
      templates << Template.default
      
      # If the user is an Org Admin look for customizations to funder templates
      customizations = []
      unless current_user.can_super_admin?
        templates.each do |funder_template|
          customization = Template.org_customizations(funder_template.id, current_user.org_id)
          customizations << customization if customization.present?
        end
      end
      
      # Gather up all of the publication dates for the live versions of each template.
      published = {}
      templates.each do |template|
        live = Template.live(template.dmptemplate_id)
        published[template.dmptemplate_id] = live.updated_at if live.present?
      end
      
      paginable_renderise(partial: 'funder_templates_list', scope: templates, 
        locals: {current_org: current_user.org.id, customizations: customizations, published: published})
    end
    
    # GET /org_admin/templates/orgs/:page  (AJAX)
    # -----------------------------------------------------
    def orgs
      authorize Template
      valid_orgs = current_user.can_super_admin? ? Org.not_funder : Org.find(current_user.org)
      if params[:page] == 'ALL'
        templates = Template.get_latest_template_versions(valid_orgs)
      else
        templates = Template.get_latest_template_versions(valid_orgs).page(params[:page])
      end
      
      # Gather up all of the publication dates for the live versions of each template.
      published = {}
      templates.each do |template|
        live = Template.live(template.dmptemplate_id)
        published[template.dmptemplate_id] = live.updated_at if live.present?
      end
      
      paginable_renderise(partial: 'templates_list', scope: templates, locals: {current_org: current_user.org.id, published: published})
    end
    
    # PUT /org_admin/templates/:id/copy  (AJAX)
    # -----------------------------------------------------
    def copy
      @template = Template.find(params[:id])
      authorize @template

      new_copy = Template.deep_copy(@template)
      new_copy.title = "Copy of " + @template.title
      new_copy.version = 0
      new_copy.published = false
      new_copy.dmptemplate_id = loop do
        random = rand 2147483647
        break random unless Template.exists?(dmptemplate_id: random)
      end

      if new_copy.save
        flash[:notice] = 'Template was successfully copied.'
        redirect_to edit_org_admin_template_path(id: new_copy.id, edit: true), notice: _('Information was successfully created.')
      else
        flash[:alert] = failed_create_error(new_copy, _('template'))
      end

    end
    
    # PUT /org_admin/templates/:id/publish  (AJAX)
    # -----------------------------------------------------
    def publish
      @template = Template.find(params[:id])
      authorize @template

      current = Template.current(@template.dmptemplate_id)

      # Only allow the current version to be updated
      if current != @template
        redirect_to org_admin_templates_path, alert: _('You can not publish a historical version of this template.')

      else
        # Unpublish the older published version if there is one
        live = Template.live(@template.dmptemplate_id)
        if !live.nil? and self != live
          live.published = false
          live.save!
        end
        # Set the dirty flag to false
        @template.dirty = false
        @template.published = true
        @template.save

        flash[:notice] = _('Your template has been published and is now available to users.')

        redirect_to org_admin_templates_path
      end
    end

    # PUT /org_admin/templates/:id/unpublish  (AJAX)
    # -----------------------------------------------------
    def unpublish
      template = Template.find(params[:id])
      authorize template

      # Unpublish the live version
      @template = Template.live(template.dmptemplate_id)

      if @template.nil?
        flash[:alert] = _('That template is not currently published.')
      else
        @template.published = false
        @template.save
        flash[:notice] = _('Your template is no longer published. Users will not be able to create new DMPs for this template until you re-publish it')
      end

      redirect_to org_admin_templates_path
    end
    
    # PUT /org_admin/template_options  (AJAX)
    # Collect all of the templates available for the org+funder combination
    # --------------------------------------------------------------------------
    def template_options()
      org_id = (plan_params[:org_id] == '-1' ? '' : plan_params[:org_id])
      funder_id = (plan_params[:funder_id] == '-1' ? '' : plan_params[:funder_id])
      authorize Template.new
    
      templates = []

      if org_id.present? || funder_id.present?
        if funder_id.blank?
          # Load the org's template(s)
          if org_id.present?
            org = Org.find(org_id)
            templates = Template.valid.where(published: true, org: org, customization_of: nil).to_a
          end

        else
          funder = Org.find(funder_id)
          # Load the funder's template(s)
          templates = Template.valid.where(published: true, org: funder).to_a

          if org_id.present?
            org = Org.find(org_id)

            # Swap out any organisational cusotmizations of a funder template
            templates.each do |tmplt|
              customization = Template.valid.find_by(published: true, org: org, customization_of: tmplt.dmptemplate_id)
              if customization.present? && tmplt.updated_at < customization.created_at
                templates.delete(tmplt)
                templates << customization
              end
            end
          end
        end
      end

      # If no templates were available use the generic templates
      if templates.empty?
        templates << Template.where(is_default: true, published: true).first
      end
      templates = (templates.count > 0 ? templates.sort{|x,y| x.title <=> y.title} : [])
    
      render json: {"templates": templates.collect{|t| {id: t.id, title: t.title} }}.to_json
    end

    
    # ======================================================
    private
    def plan_params
      params.require(:plan).permit(:org_id, :funder_id)
    end
  end
end