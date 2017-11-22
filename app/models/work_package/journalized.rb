#-- encoding: UTF-8

#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

module WorkPackage::Journalized
  extend ActiveSupport::Concern

  included do
    acts_as_journalized calculate: -> { { parent_id: parent && parent.id } }

    # This one is here only to ease reading
    module JournalizedProcs
      def self.event_title
        Proc.new do |o|
          title = o.to_s
          title << " (#{o.status.name})" if o.status.present?

          title
        end
      end

      def self.event_name
        Proc.new do |o|
          I18n.t(o.event_type.underscore, scope: 'events')
        end
      end

      def self.event_type
        Proc.new do |o|
          journal = o.last_journal
          t = 'work_package'

          t << if journal && journal.details.empty? && !journal.initial?
                 '-note'
               else
                 status = Status.find_by(id: o.status_id)

                 status.try(:is_closed?) ? '-closed' : '-edit'
               end
          t
        end
      end

      def self.event_url
        Proc.new do |o|
          { controller: :work_packages, action: :show, id: o.id }
        end
      end
    end

    acts_as_event title: JournalizedProcs.event_title,
                  type: JournalizedProcs.event_type,
                  name: JournalizedProcs.event_name,
                  url: JournalizedProcs.event_url

    register_on_journal_formatter(:id, 'parent_id')
    register_on_journal_formatter(:fraction, 'estimated_hours')
    register_on_journal_formatter(:decimal, 'done_ratio')
    register_on_journal_formatter(:diff, 'description')
    register_on_journal_formatter(:attachment, /attachments_?\d+/)
    register_on_journal_formatter(:custom_field, /custom_fields_\d+/)

    # Joined
    register_on_journal_formatter :named_association, :parent_id, :project_id,
                                  :status_id, :type_id,
                                  :assigned_to_id, :priority_id,
                                  :category_id, :fixed_version_id,
                                  :planning_element_status_id,
                                  :author_id, :responsible_id
    register_on_journal_formatter :datetime, :start_date, :due_date
    register_on_journal_formatter :plaintext, :subject

    # acts_as_journalized will create an initial journal on wp creation
    # and touch the journaled object:
    # journal.rb:47
    #
    # This will result in optimistic locking increasing the lock_version attribute to 1.
    # In order to avoid stale object errors we reload the attributes in question
    # after the wp is created.
    # As after_create is run before after_save, and journal creation is triggered by an
    # after_save hook, we rely on after_save and a specific version here.
    after_save :reload_lock_and_timestamps, if: Proc.new { |wp| wp.lock_version.zero? }

    def reload_lock_and_timestamps
      # avoid using reload(select: %i(lock_version created_at updated_at))
      # as we hook into the reload method at quite a few places
      # to wipe instance variables

      fetched_attributes = self.class.where(id: id).pluck(:lock_version, :created_at, :updated_at).first
      self.lock_version = fetched_attributes[0]
      self.created_at = fetched_attributes[1]
      self.updated_at = fetched_attributes[2]
    end
  end
end
