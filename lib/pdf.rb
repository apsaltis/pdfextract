require 'pdf-reader'
require 'nokogiri'

require_relative 'util'

# A DSL that aids in developing an understanding of the spatial
# construction of PDF pages.

class SpatialObject < Hash

  def operations
    @operations ||= {
      :grow_by => lambda { |original, modifier| original + modifier },
      :grow_by_percent => lambda { |original, pcnt| original * (1 + pcnt) },
      :shrink_by => lambda { |original, modifier| original - modifier },
      :shrink_by_percent => lambda { |original, pcnt| original * (1 - pcnt) },
      :set_to => lambda { |original, new| new },
      :set_to_percent => lambda { |original, pcnt| original * pcnt },
      :with => lambda { |original, p| p.call(original) }
    }
  end
  
  def alter op_schema
    op_schema.each_pair do |param, operations|
      operations.each_pair do |operation, value|
        self[param] = self.operations[operation].call(self[param], value)
      end
    end
  end
  
end

class Receiver

  def initialize pdf
    @pdf = pdf
    @listeners = {}
  end

  def for callback_name, &block
    @listeners[callback_name] = {:type => @pdf.operating_type, :fn => block}
  end

  def expand_listeners_to_callback_methods
    # TODO merge on callback_name
    @listeners.each_pair do |callback_name, callback_handler|
      p = proc do |*args|
        spatial_objects = callback_handler[:fn].call args
        @pdf.spatial_objects[callback_handler[:type]] << spatial_objects
      end
      
      self.class.send :define_method, callback_name, p
    end
  end

end

class Pdf
  
  attr_accessor :operating_type, :spatial_calls, :spatial_builders, :spatial_objects
  
  def method_missing name, *args
    throw StandardError.new "No such spatial type #{name}"
  end

  def spatials name, options = {}, &block
    add_spatials_method name, options, &block
  end

  def initialize
    @spatial_builders = {}
    @spatial_calls = []
    @spatial_objects = {}
    
    self.spatials :text_runs do |parser|
      parser.for :show_text_with_positioning do |data|
        so = SpatialObject.new
        so[:x] = 0
        so[:y] = 0
        so[:width] = 0
        so[:height] = 0
        so[:content] = data
        so
      end

      # TODO According to pdf-reader example, need to handle:
      # :show_text_with_positioning
      # :show_text
      # :super_show_text
      # :move_to_next_line_and_show_text
      # :set_spacing_next_line_show_text

      # TODO Somehow handle font type and size changes.
      # e.g. need to declare want to see each :show_text along
      # with the set font type and set font size that occur
      # before it.
    end

    self.spatials :images do
      parser.for :begin_inline_image_data do |data|
      end
    end
    
    self.spatials :v_margins, :depends_on => [:text_runs] do
      # Mark off ranges of the x axis. AxisMask class?
    end
    
    self.spatials :h_margins, :depends_on => [:text_runs] do
    end
    
    self.spatials :rows, :depends_on => [:h_margins] do
    end
    
    self.spatials :columns, :depends_on => [:v_margins, :rows] do
    end
    
    self.spatials :regions, :depends_on => [:text_runs] do
    end
    
    self.spatials :sections, :depends_on => [:groups, :columns] do
    end
  end

  private
  
  def add_spatials_method name, options={}, &block
    @spatial_objects[name] = []
    @spatial_builders[name] = proc { |receiver|
      @operating_type = name
      block.call receiver
    }

    p = Proc.new do
      # TODO Check for missing depends_on in the spatials_calls stack.
      
      @spatial_calls << {
        :name => name,
        :explicit => true
      }
      
      @spatial_objects[name].each do |o|
        yield o
      end
    end

    self.class.send :define_method, name, p
  end
end

def parse filename, &block
  pdf = Pdf.new
  yield pdf
  
  receiver = Receiver.new pdf
  pdf.spatial_calls.each do |spatial_call|
    pdf.spatial_builders[spatial_call[:name]].call receiver
  end
  receiver.expand_listeners_to_callback_methods

  PDF::Reader.file filename, receiver
  
  pdf
end

def view filename, options = {}, &block
  pdf = parse filename, &block

  # TODO For each called object type that was explicity called,
  # render it to an image.
end

def convert filename, options = {}, &block
  pdf = parse filename, &block

  case options[:to]
  when :xml
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.pdf {
        pdf.spatial_objects.each_pair do |type, objs|
          objs.each do |obj|
            xml.send spatial_name_to_tag_name(type.to_s)
          end
        end
      }
    end

    builder.to_xml
     
  when :html
    builder = Nokogiri::XML::Builder.new do |doc|
      doc.html {
        doc.body {
        }
      }
    end
  when :text
    ""
  end
end

# Usage

view "/Users/karl/some.pdf" do |pdf|
  pdf.text_runs do |run|
    double_height = {
      :height => {:grow_by_percent => 1},
      :y => {:shrink_by => run[:height] / 2}
    }
    run.alter double_height
  end

  pdf.sections
end

xml = convert "/Users/karl/some.pdf", :to => :xml do |pdf|
  pdf.text_runs
  pdf.sections
end

puts xml
