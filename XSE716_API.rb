class Scene_Battle
  attr_accessor :xse716_battle_main
  attr_accessor :xse716_battler_action
  def select(*args)
    return @xse716_api.select(*args)
  end
  def command_battler(battler)
    return Action.new(lambda do
      battler.blink = true
      words = $data_system.words
      command_words = [words.attack,words.skill,words.guard,words.item]
      action = @xse716_api.command_battler(battler,command_words).next
      Action.set do
        battler.blink=false
        action.cencal
      end
      loop do
        Action.pause
        break if Input.repeat?(Input::B)
        action.next.values do |command|
          break unless Input.repeat?(Input::C)
          return $xse716_action.attack(battler) if command == words.attack
          return $xse716_action.guard(battler) if command == words.guard
          unless command == words.skill ||command == words.item
            raise(RuntimeError,"未知的command类型：#{command}")
          end
          action.cencal
          is_skill = command == words.skill
          is_item = command == words.item
          action = @xse716_api.command_skill(battler).next if is_skill
          action = @xse716_api.command_item(battler).next if is_item
          loop do
            Action.pause
            break if Input.repeat?(Input::B)
            action.next.values do |id|
              break unless Input.repeat?(Input::C)
              if is_skill&&battler.skill_can_use?(id)
                return $xse716_action.skills(battler,id)
              elsif is_item&&$game_party.item_can_use?(id)
                return $xse716_action.items(battler,id)
              else
                $game_system.se_play($data_system.buzzer_se)
              end
            end
          end
          action.cencal
          action = @xse716_api.command_battler(battler,command_words).next
        end
      end
    end)
  end
  def command_party
    return Action.new(lambda do
      command_party = @xse716_api.command_party
      Action.set{command_party.cencal}
      command_party.next.values do |command|
        if Input.repeat?(Input::C)
          Action.pause(command)
        elsif Input.repeat?(Input::B)
          Action.pause("逃跑")
        else
          Action.pause
        end
      end while true
    end)
  end
  def animation(*args)
    return @xse716_api.animation(*args)
  end
  def loop_animation(*args)
    return @xse716_api.loop_animation(*args)
  end
  def show_damage(battler)
    obj = @spriteset.instance_eval{@enemy_sprites+@actor_sprites}
    target = obj.find{|s|s.battler == battler}
    sprite = Sprite_Battler.new(target.viewport,battler)
    sprite.define_singleton_method(:animation){|*args|}
    sprite.define_singleton_method(:loop_animation){|*args|}
    sprite.x = battler.screen_x
    sprite.y = battler.screen_y
    sprite.z = battler.screen_z
    battler.damage_pop = true
    sprite.update
    sprite.visible = false
    sprite.define_singleton_method(:damage){|*args|}
    @graphics_updater.push(lambda do |delete|
      return sprite.update unless sprite.instance_eval{@_damage_duration} == 0
      sprite.bitmap = nil
      sprite.dispose
      sprite = nil
      delete.call
    end)
    @xse716_status_refresh = true
  end
  def register_window(window)
    inauto = false
    updated = false
    window.instance_eval do
      define_singleton_method(:active){inauto ? false : super()}
      define_singleton_method(:update) do
        updated = true
        super()
      end
    end
    @graphics_updater.push(lambda do |delete|
      return delete.call if window.disposed?
      unless updated
        inauto = true
        window.update
        inauto=false
      end
      updated=false
    end)
  end
end
class XSE716_API
  def initialize
    @arrow_viewport = Viewport.new(0,0,Graphics.width,Graphics.height)
    @arrow_viewport.z = $scene.instance_eval{[@spriteset.viewport1.z,@spriteset.viewport2.z].max}
  end
  def select(func)
    return Action.new(lambda do
      arrows = []
      active_arrow = XSE716_Arrow_Active.new(@arrow_viewport,lambda do |battler|
        return func.exec(battler,arrows.map{|a|a.battler})
      end)
      if @last_target&&func.exec(@last_target,[])
        active_arrow.battler = @last_target
      else
        active_arrow.battler = ([]).concat($game_troop.enemies).concat($game_party.actors).find{|b|func.exec(b,[])}
      end
      Action.set do
        active_arrow.dispose
        arrows.each{|a|a.dispose}
      end
      loop do
        return arrows.map{|a|a.battler} unless active_arrow.battler
        @last_target = active_arrow.battler
        Action.pause
        if Input.repeat?(Input::C)
          arrows.push(arrow = XSE716_Arrow.new(@arrow_viewport))
          arrow.battler = active_arrow.battler
        elsif Input.repeat?(Input::B)
          return nil unless arrow = arrows.pop
          active_arrow.battler = arrow.battler
          arrow.dispose
        end
        arrows.each_index do |i|
          i = arrows.length-1-i
          next if func.exec(arrows[i].battler,arrows[0,i].map{|a|a.battler})
          arrows[i].dispose
          arrows[i]= nil
        end
        arrows.compact!
        active_arrow.update
      end
    end)
  end
  def command_party
    return Action.new(lambda do
      $scene.register_window(window = Window_PartyCommand.new)
      window.visible = true
      window.active = true
      Action.set{window.dispose}
      while true
        Action.pause(window.instance_eval{@commands}[window.index])
        window.update
      end
    end)
  end
  def command_skill(battler)
    @index_skill||=Hash.new
    return Action.new(lambda do
      $scene.register_window(window = Window_Skill.new(battler))
      window.help_window = Window_Help.new
      window.index = @index_skill[battler]||0
      Action.set do
        @index_skill[battler] = window.index
        window.help_window.dispose
        window.help_window = nil
        window.dispose
      end
      loop do
        Action.pause(window.skill.id)
        window.update
      end
    end)
  end
  def command_item(battler)
    @index_item||=Hash.new
    return Action.new(lambda do
      $scene.register_window(window = Window_Item.new)
      window.help_window = Window_Help.new
      window.index = @index_item[battler]||0
      Action.set do
        @index_item[battler] = window.index
        window.help_window.dispose
        window.help_window = nil
        window.dispose
      end
      loop do
        Action.pause(window.item.id)
        window.update
      end
    end)
  end
  def command_battler(battler,command_words)
    @index_command||=Hash.new
    return Action.new(lambda do
      $scene.register_window(window = Window_Command.new(160,command_words))
      window.index=(@index_command[battler]||=0)
      window.x = $game_party.actors.index(battler)*160
      window.y = 160
      window.index = @index_command[battler]||0
      Action.set do
        @index_command[battler] = window.index
        window.dispose
      end
      loop do
        Action.pause(command_words[window.index])
        window.update
      end
    end)
  end
  def find_sprite(b)
    obj = $scene.instance_variable_get(:@spriteset)
    obj.instance_eval{@enemy_sprites+@actor_sprites}.find{|s|s.battler == b}
  end
  def animation(battler,id)
    target = self.find_sprite(battler)
    return Action.new(lambda do
      Action.set{target.instance_variable_set(:@_collapse_duration,1)}
      target.whiten
      16.times{|i|Action.pause(i/2.0,target)}
      Action.set{}
    end) if id == 0
    return Action.new(lambda do
      sprite = Sprite_Battler.new(target.viewport,battler)
      sprite.define_singleton_method(:damage){|*args|}
      sprite.define_singleton_method(:loop_animation){|*args|}
      sprite.update
      sprite.visible =false
      sprite.animation($data_animations[id],nil)
      sprite.define_singleton_method(:animation){|*args|}
      Action.set do
        sprite.bitmap = nil
        sprite.dispose
        sprite = nil
      end
      time=0
      max = duration = sprite.instance_eval{@_animation_duration}
      until duration ==0
        frame = max-duration+1
        Action.pause(frame+1-1.0/(time+1),target)
        time+=1
        sprite.update
        d = sprite.instance_eval{@_animation_duration}
        time = 0 unless duration == d
        duration = d
      end
    end)
  end
  def loop_animation(battler,id)
    g = self.animation(battler,id)
    return Action.new(lambda do
      Action.set{g.cencal}
      loop do
        g.values{|*args|Action.pause(*args)} while g.next.running?
        g = self.animation(battler,id)
      end
    end)
  end
end