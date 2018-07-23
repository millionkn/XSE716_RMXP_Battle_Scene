class Scene_Battle
  attr_accessor :xse716_battle_main
  attr_accessor :xse716_battler_action
  def select(*args)
    return @xse716_api.select(*args)
  end
  def command_battler(*args)
    return @xse716_api.command_battler(*args)
  end
  def command_party
    return @xse716_api.command_party
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
      window = Scene_Battle::XSE716_Window_Proxy.new(Window_PartyCommand.new)
      window.visible = true
      Action.set{window.dispose}
      return self.wait_window(window){|w|w.index}
    end)
  end
  def command_skill(battler)
    @index_skill||=Hash.new
    return Action.new(lambda do
      skill_window = XSE716_Window_Proxy.new(Window_Skill.new(battler))
      skill_window.help_window = Window_Help.new
      skill_window.index = @index_skill[battler]||0
      cencal = Action.set do
        @index_skill[battler] = skill_window.index
        skill_window.help_window.dispose
        skill_window.help_window = nil
        skill_window.dispose
      end
      return self.wait_window(skill_window) do |window|
        skill_id = window.skill.id
        return lambda{|battler|return $xse716_action.skills(battler,skill_id)}
      end
    end)
  end
  def command_item
    @index_item||=0
    return Action.new(lambda do
      item_window = XSE716_Window_Proxy.new(Window_Item.new)
      item_window.help_window = Window_Help.new
      item_window.index = @index_item
      cencal = Action.set do
        @index_item = item_window.index
        item_window.help_window.dispose
        item_window.help_window = nil
        item_window.dispose
      end
      return self.wait_window(item_window) do |window|
        item_id = window.item.id
        return lambda{|battler|return $xse716_action.items(battler,item_id)}
      end
    end)
  end
  def command_battler(battler)
    @index_command ||= Hash.new
    return Action.new(lambda do
      battler.blink = true
      words = $data_system.words
      command_words = [words.attack,words.skill,words.guard,words.item]
      command_window = XSE716_Window_Proxy.new(Window_Command.new(160,command_words))
      command_window.index=(@index_command[battler]||=0)
      command_window.x = $game_party.actors.index(battler)*160
      command_window.y = 160
      action = nil
      Action.set do
        @index_command[battler] = command_window.index
        action.cencal if action
        command_window.dispose
        battler.blink = false
      end
      loop do
        command_window.visible = true
        return unless index = self.wait_window(command_window){|w|w.index}
        case command_words[index]
        when words.attack
          return $xse716_action.method(:attack)
        when words.skill
          command_window.visible = false
          $game_system.se_play($data_system.decision_se)
          action = self.command_skill(battler)
          Action.pause while action.next.running?
          command_window.visible = true
          action.values{|ret|return ret if ret}
          $game_system.se_play($data_system.cancel_se)
        when words.guard
          return $xse716_action.method(:guard)
        when words.item
          command_window.visible = false
          $game_system.se_play($data_system.decision_se)
          action = self.command_item
          Action.pause while action.next.running?
          command_window.visible = true
          action.values{|ret|return ret if ret}
          $game_system.se_play($data_system.cancel_se)
        else
          throw(RuntimeError,"窗口响应方式未定义:#{id}")
        end
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
  def wait_window(window,&fun)
    loop do
      Action.pause
      window.update
      if Input::trigger?(Input::C)
        return fun.exec(window)
      elsif Input.trigger?(Input::B)
        return nil
      end
    end
  end
end